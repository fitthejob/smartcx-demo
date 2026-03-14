"""
order-lookup Lambda
Triggered by Amazon Connect contact flow (Invoke AWS Lambda block).
Looks up an order by orderId (from Lex slot) or by caller phone number (ANI) via GSI.

Connect expects all string values in the response — no integers or booleans.
The entire handler is wrapped in try/except so Connect never receives an unhandled
exception (Connect cannot gracefully handle Lambda errors from the invoke block).
"""
import json
import logging
import os

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
TABLE_NAME = os.environ["ORDERS_TABLE_NAME"]
PHONE_INDEX = os.environ["ORDERS_PHONE_INDEX_NAME"]


def log(level, msg, **kwargs):
    logger.log(level, json.dumps({"level": logging.getLevelName(level), "msg": msg, **kwargs}))


def _format_date(date_str):
    """Convert YYYY-MM-DD to 'Month DD, YYYY' for natural TTS playback."""
    if not date_str:
        return ""
    try:
        from datetime import datetime
        dt = datetime.strptime(date_str, "%Y-%m-%d")
        return dt.strftime("%B %-d, %Y")
    except Exception:
        return date_str


def _lookup_by_order_id(table, order_id):
    response = table.get_item(Key={"orderId": order_id})
    return response.get("Item")


def _lookup_by_phone(table, phone):
    """Return the most recent order for a caller phone number via GSI."""
    response = table.query(
        IndexName=PHONE_INDEX,
        KeyConditionExpression=Key("customerPhone").eq(phone),
    )
    items = response.get("Items", [])
    if not items:
        return None
    # Sort by orderDate descending and return the newest
    items.sort(key=lambda x: x.get("orderDate", ""), reverse=True)
    return items[0]


def _build_response(order):
    """Build the flat string dict returned to Connect."""
    first_name = order.get("customerName", "").split()[0] if order.get("customerName") else ""
    return {
        "orderFound": "true",
        "orderId": str(order.get("orderId", "")),
        "status": str(order.get("status", "")),
        "carrier": str(order.get("carrier", "")),
        "trackingNumber": str(order.get("trackingNumber", "")),
        "estimatedDelivery": _format_date(order.get("estimatedDelivery", "")),
        "customerName": first_name,
    }


def handler(event, context):
    try:
        parameters = event.get("Details", {}).get("Parameters", {})
        contact_data = event.get("Details", {}).get("ContactData", {})
        caller_phone = contact_data.get("CustomerEndpoint", {}).get("Address", "")
        order_id = parameters.get("orderId", "").strip()

        log(logging.INFO, "order-lookup invoked", orderId=order_id, callerPhone=caller_phone)

        table = dynamodb.Table(TABLE_NAME)

        if order_id:
            order = _lookup_by_order_id(table, order_id)
            lookup_type = "orderId"
        else:
            order = _lookup_by_phone(table, caller_phone)
            lookup_type = "phone"

        if not order:
            log(logging.INFO, "order not found", lookupType=lookup_type,
                orderId=order_id, callerPhone=caller_phone)
            return {"orderFound": "false"}

        response = _build_response(order)
        log(logging.INFO, "order found", lookupType=lookup_type, orderId=response["orderId"],
            status=response["status"])
        return response

    except Exception as e:
        log(logging.ERROR, "unhandled exception", error=str(e))
        return {"orderFound": "false"}
