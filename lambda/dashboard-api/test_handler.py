"""
Unit tests for dashboard-api Lambda.
Uses moto to mock DynamoDB — no real AWS calls made.
Connect API (/queues/live) is tested with mocking.
"""
import json
import os
from datetime import datetime, timezone
from unittest.mock import patch, MagicMock

import boto3
import pytest
from moto import mock_aws


CONTACTS_TABLE = "test-contacts"
FLAGGED_TABLE = "test-flagged"

os.environ["CONTACTS_TABLE_NAME"] = CONTACTS_TABLE
os.environ["CONTACTS_DATE_INDEX_NAME"] = "date-index"
os.environ["FLAGGED_TABLE_NAME"] = FLAGGED_TABLE
os.environ["FLAGGED_DATE_INDEX_NAME"] = "date-index"
os.environ["CONNECT_INSTANCE_ID"] = "test-instance-id"


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


def _seed_contact(table, contact_id, sentiment, score, date, duration=120):
    table.put_item(Item={
        "contactId": contact_id,
        "timestamp": f"{date}T12:00:00Z",
        "contactDate": date,
        "channel": "VOICE",
        "sentiment": sentiment,
        "sentimentScore": str(score),
        "duration": duration,
        "queueName": "SupportQueue",
        "agentId": "agent-001",
        "transcriptUrl": "s3://test/recording.wav",
    })


def _api_event(path, method="GET"):
    return {"httpMethod": method, "path": path}


@mock_aws
def test_get_contacts_returns_list():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    table = dynamodb.Table(CONTACTS_TABLE)
    _seed_contact(table, "c-001", "POSITIVE", 0.8, today)
    _seed_contact(table, "c-002", "NEGATIVE", -0.7, today)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/contacts"), {})
    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert len(body["contacts"]) == 2
    assert body["total"] == 2


@mock_aws
def test_get_contacts_flagged():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    flagged_table = dynamodb.Table(FLAGGED_TABLE)
    _seed_contact(flagged_table, "f-001", "NEGATIVE", -0.8, today)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/contacts/flagged"), {})
    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert len(body["contacts"]) == 1


@mock_aws
def test_get_metrics():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    table = dynamodb.Table(CONTACTS_TABLE)
    _seed_contact(table, "m-001", "POSITIVE", 0.8,  today, duration=100)
    _seed_contact(table, "m-002", "NEUTRAL",  0.0,  today, duration=200)
    _seed_contact(table, "m-003", "NEGATIVE", -0.9, today, duration=300)

    flagged_table = dynamodb.Table(FLAGGED_TABLE)
    _seed_contact(flagged_table, "m-003", "NEGATIVE", -0.9, today)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/metrics"), {})
    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert body["contactsToday"] == 3
    assert body["flaggedToday"] == 1
    assert body["avgHandleTimeSeconds"] == 200  # (100+200+300)/3
    assert body["sentimentBreakdown"]["POSITIVE"] == 1
    assert body["sentimentBreakdown"]["NEUTRAL"] == 1
    assert body["sentimentBreakdown"]["NEGATIVE"] == 1


@mock_aws
def test_get_metrics_empty_tables():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/metrics"), {})
    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    assert body["contactsToday"] == 0
    assert body["avgHandleTimeSeconds"] == 0
    assert body["flaggedToday"] == 0


@mock_aws
def test_options_preflight_returns_200():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/contacts", method="OPTIONS"), {})
    assert result["statusCode"] == 200
    assert "Access-Control-Allow-Origin" in result["headers"]


@mock_aws
def test_unknown_path_returns_404():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    import importlib
    import handler as h
    importlib.reload(h)

    result = h.handler(_api_event("/unknown"), {})
    assert result["statusCode"] == 404


@mock_aws
def test_queues_live_returns_all_three_combos():
    """
    /queues/live should always return SupportQueue/VOICE, SupportQueue/CHAT,
    BillingQueue/VOICE — even if Connect returns no data (all zeros).
    """
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb, CONTACTS_TABLE)
    _create_table(dynamodb, FLAGGED_TABLE)

    mock_connect = MagicMock()
    mock_connect.get_paginator.return_value.paginate.return_value = [{
        "QueueSummaryList": [
            {"Name": "SupportQueue", "Id": "sq-001"},
            {"Name": "BillingQueue", "Id": "bq-001"},
        ]
    }]
    mock_connect.get_current_metric_data.return_value = {"MetricResults": []}

    import importlib
    import handler as h
    importlib.reload(h)

    with patch.object(h, "connect_client", mock_connect):
        h._queue_id_cache = {}  # reset cache
        result = h.handler(_api_event("/queues/live"), {})

    assert result["statusCode"] == 200
    body = json.loads(result["body"])
    queue_names = [(q["queueName"], q["channel"]) for q in body["queues"]]
    assert ("SupportQueue", "VOICE") in queue_names
    assert ("SupportQueue", "CHAT") in queue_names
    assert ("BillingQueue", "VOICE") in queue_names
