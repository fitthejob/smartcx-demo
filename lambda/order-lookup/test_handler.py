"""
Unit tests for order-lookup Lambda.
Uses moto to mock DynamoDB — no real AWS calls made.
"""
import json
import os
import pytest

import boto3
from moto import mock_aws


TABLE_NAME = "test-orders"
PHONE_INDEX = "customerPhone-index"

os.environ["ORDERS_TABLE_NAME"] = TABLE_NAME
os.environ["ORDERS_PHONE_INDEX_NAME"] = PHONE_INDEX


def _create_table(dynamodb):
    return dynamodb.create_table(
        TableName=TABLE_NAME,
        KeySchema=[{"AttributeName": "orderId", "KeyType": "HASH"}],
        AttributeDefinitions=[
            {"AttributeName": "orderId",       "AttributeType": "S"},
            {"AttributeName": "customerPhone", "AttributeType": "S"},
        ],
        GlobalSecondaryIndexes=[{
            "IndexName": PHONE_INDEX,
            "KeySchema": [{"AttributeName": "customerPhone", "KeyType": "HASH"}],
            "Projection": {"ProjectionType": "ALL"},
        }],
        BillingMode="PAY_PER_REQUEST",
    )


def _seed(table):
    table.put_item(Item={
        "orderId": "ORD-001",
        "customerPhone": "+16165550101",
        "customerName": "Jane Smith",
        "status": "SHIPPED",
        "carrier": "UPS",
        "trackingNumber": "1Z999",
        "estimatedDelivery": "2025-03-18",
        "orderDate": "2025-03-12",
    })
    table.put_item(Item={
        "orderId": "ORD-002",
        "customerPhone": "+16165550101",
        "customerName": "Jane Smith",
        "status": "DELIVERED",
        "carrier": "FedEx",
        "trackingNumber": "2Z888",
        "estimatedDelivery": "2025-03-01",
        "orderDate": "2025-02-25",
    })


@mock_aws
def test_lookup_by_order_id_found():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = _create_table(dynamodb)
    _seed(table)

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": "+16165550101"}},
            "Parameters": {"orderId": "ORD-001"},
        }
    }
    result = handler(event, {})

    assert result["orderFound"] == "true"
    assert result["orderId"] == "ORD-001"
    assert result["status"] == "SHIPPED"
    assert result["carrier"] == "UPS"
    assert result["customerName"] == "Jane"


@mock_aws
def test_lookup_by_order_id_not_found():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb)

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": "+16165550101"}},
            "Parameters": {"orderId": "ORD-NOTEXIST"},
        }
    }
    result = handler(event, {})
    assert result["orderFound"] == "false"


@mock_aws
def test_lookup_by_phone_returns_most_recent():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = _create_table(dynamodb)
    _seed(table)

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": "+16165550101"}},
            "Parameters": {},
        }
    }
    result = handler(event, {})

    assert result["orderFound"] == "true"
    # ORD-001 (2025-03-12) is more recent than ORD-002 (2025-02-25)
    assert result["orderId"] == "ORD-001"


@mock_aws
def test_lookup_by_phone_not_found():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    _create_table(dynamodb)

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": "+16165559999"}},
            "Parameters": {},
        }
    }
    result = handler(event, {})
    assert result["orderFound"] == "false"


@mock_aws
def test_never_raises_on_exception():
    """Handler must always return a dict — never raise — even if DynamoDB is misconfigured."""
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    # Intentionally do NOT create the table

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": "+16165550101"}},
            "Parameters": {"orderId": "ORD-001"},
        }
    }
    result = handler(event, {})
    assert result == {"orderFound": "false"}


@mock_aws
def test_estimated_delivery_formatted_for_tts():
    dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
    table = _create_table(dynamodb)
    _seed(table)

    from handler import handler
    event = {
        "Details": {
            "ContactData": {"CustomerEndpoint": {"Address": ""}},
            "Parameters": {"orderId": "ORD-001"},
        }
    }
    result = handler(event, {})
    # Should be human-readable for TTS, not raw YYYY-MM-DD
    assert result["estimatedDelivery"] == "March 18, 2025"
