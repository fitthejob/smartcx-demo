"""
Unit tests for contact-lens-handler Lambda.
Uses moto to mock DynamoDB and SNS — no real AWS calls made.
"""
import importlib.util
import os
from pathlib import Path

import boto3
import pytest
from moto import mock_aws

# Set env vars before loading the handler module
CONTACTS_TABLE = "test-contacts"
FLAGGED_TABLE = "test-flagged"
SNS_TOPIC_ARN = "arn:aws:sns:us-east-1:123456789012:test-alerts"
os.environ["CONTACTS_TABLE_NAME"] = CONTACTS_TABLE
os.environ["FLAGGED_TABLE_NAME"] = FLAGGED_TABLE
os.environ["SNS_ALERT_TOPIC_ARN"] = SNS_TOPIC_ARN
os.environ["SENTIMENT_THRESHOLD"] = "-0.5"
os.environ["RECORDINGS_BUCKET_NAME"] = "test-recordings"

# Load handler module from its explicit path
_handler_path = Path(__file__).parent / "handler.py"
_spec = importlib.util.spec_from_file_location("contact_lens_handler", _handler_path)
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)
handler = _mod.handler


def _make_event(contact_id="abc-123", status="SUCCEEDED", customer_score=-0.72,
                channel="VOICE", agent="agent-001", queue="SupportQueue"):
    return {
        "source": "aws.connect",
        "detail-type": "Contact Lens Analysis State Change",
        "detail": {
            "ContactId": contact_id,
            "InstanceId": "inst-001",
            "Channel": channel,
            "AnalysisStatus": status,
            "ConversationCharacteristics": {
                "Sentiment": {
                    "OverallSentiment": {
                        "AGENT": 0.1,
                        "CUSTOMER": customer_score,
                    }
                },
                "TotalConversationDurationMillis": 187000,
            },
            "Agent": {"AgentUsername": agent},
            "Queue": {"Name": queue, "Arn": "arn:aws:connect:..."},
            "RecordingsS3BucketName": "test-recordings",
            "RecordingS3KeyName": f"{contact_id}/recording.wav",
        }
    }


def _create_table(dynamodb, table_name):
    return dynamodb.create_table(
        TableName=table_name,
        KeySchema=[
            {"AttributeName": "contactId", "KeyType": "HASH"},
            {"AttributeName": "timestamp", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "contactId",  "AttributeType": "S"},
            {"AttributeName": "timestamp",  "AttributeType": "S"},
            {"AttributeName": "contactDate", "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[{
            "IndexName": "date-index",
            "KeySchema": [
                {"AttributeName": "contactDate", "KeyType": "HASH"},
                {"AttributeName": "timestamp",   "KeyType": "RANGE"},
            ],
            "Projection": {"ProjectionType": "ALL"},
        }],
        BillingMode="PAY_PER_REQUEST",
    )


@mock_aws
def test_negative_sentiment_writes_both_tables_and_publishes_sns():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    sns = boto3.client("sns", region_name="us-east-1")
    sns.create_topic(Name="test-alerts")

    # Re-init module-level boto3 clients inside the mock context
    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _mod.sns_client = boto3.client("sns", region_name="us-east-1")

    handler(_make_event(customer_score=-0.72), {})

    contacts_table = dynamodb.Table(CONTACTS_TABLE)
    result = contacts_table.scan()
    assert len(result["Items"]) == 1
    assert result["Items"][0]["sentiment"] == "NEGATIVE"

    flagged_table = dynamodb.Table(FLAGGED_TABLE)
    assert len(flagged_table.scan()["Items"]) == 1


@mock_aws
def test_positive_sentiment_writes_contacts_only():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    sns = boto3.client("sns", region_name="us-east-1")
    sns.create_topic(Name="test-alerts")

    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _mod.sns_client = boto3.client("sns", region_name="us-east-1")

    handler(_make_event(customer_score=0.85), {})

    assert len(dynamodb.Table(CONTACTS_TABLE).scan()["Items"]) == 1
    assert len(dynamodb.Table(FLAGGED_TABLE).scan()["Items"]) == 0


@mock_aws
def test_neutral_sentiment_not_flagged():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    sns = boto3.client("sns", region_name="us-east-1")
    sns.create_topic(Name="test-alerts")

    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _mod.sns_client = boto3.client("sns", region_name="us-east-1")

    handler(_make_event(customer_score=0.0), {})

    assert len(dynamodb.Table(FLAGGED_TABLE).scan()["Items"]) == 0


@mock_aws
def test_non_succeeded_event_ignored():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")

    handler(_make_event(status="IN_PROGRESS"), {})

    assert len(dynamodb.Table(CONTACTS_TABLE).scan()["Items"]) == 0


@mock_aws
def test_duplicate_event_idempotent():
    """Second invocation with same contactId should not write a duplicate record."""
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    sns = boto3.client("sns", region_name="us-east-1")
    sns.create_topic(Name="test-alerts")

    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _mod.sns_client = boto3.client("sns", region_name="us-east-1")

    event = _make_event(contact_id="dup-001", customer_score=-0.8)
    handler(event, {})
    handler(event, {})  # second invocation — should be a no-op

    assert len(dynamodb.Table(CONTACTS_TABLE).scan()["Items"]) == 1
    assert len(dynamodb.Table(FLAGGED_TABLE).scan()["Items"]) == 1


@mock_aws
def test_missing_sentiment_data_skips_record():
    """Events without sentiment data (very short calls) should be skipped gracefully."""
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    _mod.dynamodb = boto3.resource("dynamodb", region_name="us-east-1")

    event = {
        "detail": {
            "ContactId": "short-call",
            "AnalysisStatus": "SUCCEEDED",
            "Channel": "VOICE",
            "ConversationCharacteristics": {},
            "Agent": {"AgentUsername": "agent-001"},
            "Queue": {"Name": "SupportQueue"},
            "RecordingsS3BucketName": "test-recordings",
            "RecordingS3KeyName": "short-call/recording.wav",
        }
    }

    handler(event, {})  # should not raise

    assert len(dynamodb.Table(CONTACTS_TABLE).scan()["Items"]) == 0
