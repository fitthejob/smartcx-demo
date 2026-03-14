"""
contact-lens-handler Lambda
Triggered by EventBridge on Contact Lens Analysis State Change (SUCCEEDED).

Behavior:
1. Ignores events where AnalysisStatus != SUCCEEDED
2. Extracts sentiment, duration, agent, queue, channel from the event
3. Always writes to smartcx-contacts (idempotent — ConditionExpression prevents duplicates)
4. If sentiment < SENTIMENT_THRESHOLD: writes to smartcx-flagged-contacts and publishes SNS alert
5. On ConditionalCheckFailedException (duplicate event): logs WARN and skips SNS publish
"""
import json
import logging
import os
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
sns_client = boto3.client("sns")

CONTACTS_TABLE = os.environ["CONTACTS_TABLE_NAME"]
FLAGGED_TABLE = os.environ["FLAGGED_TABLE_NAME"]
SNS_TOPIC_ARN = os.environ["SNS_ALERT_TOPIC_ARN"]
SENTIMENT_THRESHOLD = float(os.environ.get("SENTIMENT_THRESHOLD", "-0.5"))
RECORDINGS_BUCKET = os.environ.get("RECORDINGS_BUCKET_NAME", "")


def log(level, msg, **kwargs):
    logger.log(level, json.dumps({"level": logging.getLevelName(level), "msg": msg, **kwargs}))


def _sentiment_label(score):
    if score > 0.2:
        return "POSITIVE"
    if score < -0.2:
        return "NEGATIVE"
    return "NEUTRAL"


def _put_item_idempotent(table_name, item):
    """
    Write item to DynamoDB only if contactId does not already exist.
    Returns True on success, False if item already existed (duplicate event).
    Raises on any other error.
    """
    table = dynamodb.Table(table_name)
    try:
        table.put_item(
            Item=item,
            ConditionExpression="attribute_not_exists(contactId)",
        )
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return False
        raise


def handler(event, context):
    detail = event.get("detail", {})

    # Ignore non-SUCCEEDED events
    analysis_status = detail.get("AnalysisStatus", "")
    if analysis_status != "SUCCEEDED":
        log(logging.INFO, "ignoring non-SUCCEEDED event", analysisStatus=analysis_status)
        return

    contact_id = detail.get("ContactId", "")
    channel = detail.get("Channel", "VOICE")
    instance_id = detail.get("InstanceId", "")

    log(logging.INFO, "processing contact lens event", contactId=contact_id, channel=channel)

    # Extract sentiment — guard against missing keys (short calls may lack sentiment data)
    conv = detail.get("ConversationCharacteristics", {})
    sentiment_data = conv.get("Sentiment", {}).get("OverallSentiment", {})
    customer_score = sentiment_data.get("CUSTOMER")

    if customer_score is None:
        log(logging.WARNING, "sentiment data absent, skipping record", contactId=contact_id)
        return

    customer_score = float(customer_score)
    sentiment_label = _sentiment_label(customer_score)

    duration_ms = conv.get("TotalConversationDurationMillis", 0)
    duration_seconds = int(duration_ms / 1000)

    agent_id = detail.get("Agent", {}).get("AgentUsername", "")
    queue_name = detail.get("Queue", {}).get("Name", "")

    # Construct approximate transcript URL
    # Note: Contact Lens transcript is a separate S3 object from the recording.
    # The RecordingS3KeyName points to the audio file. We construct the URL as a best-effort
    # reference; the actual transcript key follows a different naming convention.
    bucket = detail.get("RecordingsS3BucketName") or RECORDINGS_BUCKET
    key = detail.get("RecordingS3KeyName", f"{contact_id}/recording.wav")
    transcript_url = f"s3://{bucket}/{key}" if bucket else ""

    now = datetime.now(timezone.utc)
    timestamp = now.isoformat(timespec="seconds").replace("+00:00", "Z")
    contact_date = now.strftime("%Y-%m-%d")

    contact_record = {
        "contactId": contact_id,
        "timestamp": timestamp,
        "contactDate": contact_date,
        "channel": channel,
        "sentiment": sentiment_label,
        "sentimentScore": str(customer_score),  # DynamoDB stores as string for Connect compat
        "duration": duration_seconds,
        "queueName": queue_name,
        "agentId": agent_id,
        "transcriptUrl": transcript_url,
    }

    # Always write to contacts table
    written = _put_item_idempotent(CONTACTS_TABLE, contact_record)
    if not written:
        log(logging.WARNING, "duplicate contact event — contacts record already exists",
            contactId=contact_id)
        # Skip SNS publish too — alert was already sent on first invocation
        return

    log(logging.INFO, "contact record written", contactId=contact_id,
        sentiment=sentiment_label, score=customer_score)

    # Flag negative sentiment contacts
    if customer_score < SENTIMENT_THRESHOLD:
        flagged_record = {
            "contactId": contact_id,
            "timestamp": timestamp,
            "contactDate": contact_date,
            "sentiment": sentiment_label,
            "sentimentScore": str(customer_score),
            "agentId": agent_id,
            "queueName": queue_name,
            "transcriptUrl": transcript_url,
        }

        flagged_written = _put_item_idempotent(FLAGGED_TABLE, flagged_record)
        if not flagged_written:
            log(logging.WARNING, "duplicate contact event — flagged record already exists",
                contactId=contact_id)
            return

        # Publish SNS alert
        message = (
            f"Negative sentiment alert\n\n"
            f"Contact ID : {contact_id}\n"
            f"Agent      : {agent_id}\n"
            f"Queue      : {queue_name}\n"
            f"Score      : {customer_score:.2f}\n"
            f"Channel    : {channel}\n"
            f"Time       : {timestamp}"
        )
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject="SmartCX Alert — Negative Sentiment Detected",
            Message=message,
        )
        log(logging.INFO, "SNS alert published", contactId=contact_id, score=customer_score)
