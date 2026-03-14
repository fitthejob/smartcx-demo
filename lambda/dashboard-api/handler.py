"""
dashboard-api Lambda
Triggered by API Gateway (REST, Lambda proxy integration).

Endpoints:
  GET /contacts          — last 50 contacts (all sentiments) sorted by timestamp desc
  GET /contacts/flagged  — flagged (negative sentiment) contacts
  GET /metrics           — contacts today, avg handle time, sentiment breakdown, flagged count
  GET /queues/live       — real-time queue depth and agent states via Connect API

All reads use the date-index GSI — never Scan.
Queue IDs for /queues/live are resolved at module load time and cached.
"""
import json
import logging
import os
from datetime import datetime, timezone, timedelta

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")
connect_client = boto3.client("connect")

CONTACTS_TABLE = os.environ["CONTACTS_TABLE_NAME"]
CONTACTS_DATE_INDEX = os.environ["CONTACTS_DATE_INDEX_NAME"]
FLAGGED_TABLE = os.environ["FLAGGED_TABLE_NAME"]
FLAGGED_DATE_INDEX = os.environ["FLAGGED_DATE_INDEX_NAME"]
CONNECT_INSTANCE_ID = os.environ.get("CONNECT_INSTANCE_ID", "")

# Cache queue name → ID at module load time (reused across warm invocations)
_queue_id_cache = {}


def log(level, msg, **kwargs):
    logger.log(level, json.dumps({"level": logging.getLevelName(level), "msg": msg, **kwargs}))


def _cors_headers():
    # TODO: production hardening — restrict to CloudFront domain
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type",
        "Access-Control-Allow-Methods": "GET,OPTIONS",
        "Content-Type": "application/json",
    }


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": _cors_headers(),
        "body": json.dumps(body),
    }


def _today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _yesterday():
    return (datetime.now(timezone.utc) - timedelta(days=1)).strftime("%Y-%m-%d")


def _query_by_date(table_name, index_name, date_str, limit=50):
    """Query table using date-index GSI for a given date, sorted by timestamp descending."""
    table = dynamodb.Table(table_name)
    response = table.query(
        IndexName=index_name,
        KeyConditionExpression=Key("contactDate").eq(date_str),
        ScanIndexForward=False,  # descending by sort key (timestamp)
        Limit=limit,
    )
    return response.get("Items", [])


def _get_contacts(limit=50):
    """
    Return up to `limit` contacts sorted by timestamp desc.
    Queries today first; if fewer than limit results, also queries yesterday.
    This is a simplification suitable for demo — documented in code.
    """
    items = _query_by_date(CONTACTS_TABLE, CONTACTS_DATE_INDEX, _today(), limit)
    if len(items) < limit:
        yesterday_items = _query_by_date(
            CONTACTS_TABLE, CONTACTS_DATE_INDEX, _yesterday(), limit - len(items)
        )
        items.extend(yesterday_items)
    items.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    return items[:limit]


def _get_flagged(limit=50):
    items = _query_by_date(FLAGGED_TABLE, FLAGGED_DATE_INDEX, _today(), limit)
    if len(items) < limit:
        yesterday_items = _query_by_date(
            FLAGGED_TABLE, FLAGGED_DATE_INDEX, _yesterday(), limit - len(items)
        )
        items.extend(yesterday_items)
    items.sort(key=lambda x: x.get("timestamp", ""), reverse=True)
    return items[:limit]


def _get_metrics():
    today = _today()
    contacts = _query_by_date(CONTACTS_TABLE, CONTACTS_DATE_INDEX, today, limit=1000)
    flagged = _query_by_date(FLAGGED_TABLE, FLAGGED_DATE_INDEX, today, limit=1000)

    total = len(contacts)
    flagged_count = len(flagged)

    durations = [int(c.get("duration", 0)) for c in contacts if c.get("duration")]
    avg_handle = int(sum(durations) / len(durations)) if durations else 0

    breakdown = {"POSITIVE": 0, "NEUTRAL": 0, "NEGATIVE": 0}
    for c in contacts:
        label = c.get("sentiment", "NEUTRAL")
        if label in breakdown:
            breakdown[label] += 1

    return {
        "contactsToday": total,
        "avgHandleTimeSeconds": avg_handle,
        "sentimentBreakdown": breakdown,
        "flaggedToday": flagged_count,
    }


def _get_queue_ids():
    """
    Resolve queue names to IDs via Connect API at module load time.
    Cached at module level — reused across warm Lambda invocations.
    Only fetches STANDARD queues (excludes system queues like BasicQueue).
    """
    global _queue_id_cache
    if _queue_id_cache:
        return _queue_id_cache

    if not CONNECT_INSTANCE_ID:
        return {}

    try:
        paginator = connect_client.get_paginator("list_queues")
        cache = {}
        for page in paginator.paginate(
            InstanceId=CONNECT_INSTANCE_ID,
            QueueTypes=["STANDARD"],
        ):
            for q in page.get("QueueSummaryList", []):
                cache[q["Name"]] = q["Id"]
        _queue_id_cache = cache
        log(logging.INFO, "queue ID cache populated", queueCount=len(cache))
    except Exception as e:
        log(logging.ERROR, "failed to populate queue ID cache", error=str(e))

    return _queue_id_cache


def _get_queues_live():
    """
    Call Connect GetCurrentMetricData for SupportQueue and BillingQueue.
    Returns all three queue/channel combos, defaulting missing entries to zeros.
    GetCurrentMetricData only returns queues/channels with recent activity —
    missing entries are filled with zeros so the dashboard always shows all cards.
    """
    queue_ids = _get_queue_ids()

    target_queues = ["SupportQueue", "BillingQueue"]
    queue_id_list = [queue_ids[name] for name in target_queues if name in queue_ids]

    if not queue_id_list:
        log(logging.WARNING, "no queue IDs resolved — returning empty live data")
        return _empty_queues_response()

    try:
        response = connect_client.get_current_metric_data(
            InstanceId=CONNECT_INSTANCE_ID,
            Filters={
                "Queues": queue_id_list,
                "Channels": ["VOICE", "CHAT"],
            },
            Groupings=["QUEUE", "CHANNEL"],
            CurrentMetrics=[
                {"Name": "CONTACTS_IN_QUEUE",        "Unit": "COUNT"},
                {"Name": "OLDEST_CONTACT_AGE",        "Unit": "SECONDS"},
                {"Name": "AGENTS_AVAILABLE",          "Unit": "COUNT"},
                {"Name": "AGENTS_ON_CONTACT",         "Unit": "COUNT"},
                {"Name": "AGENTS_AFTER_CONTACT_WORK", "Unit": "COUNT"},
            ],
        )
    except Exception as e:
        log(logging.ERROR, "GetCurrentMetricData failed", error=str(e))
        return _empty_queues_response()

    # Build reverse lookup: queue_id → queue_name
    id_to_name = {v: k for k, v in queue_ids.items()}

    # Aggregate results into a dict keyed by (queue_name, channel)
    result_map = {}
    for collection in response.get("MetricResults", []):
        dims = collection.get("Dimensions", {})
        queue_info = dims.get("Queue", {})
        queue_id = queue_info.get("Id", "")
        channel = dims.get("Channel", "VOICE")
        queue_name = id_to_name.get(queue_id, queue_id)

        entry = result_map.setdefault((queue_name, channel), _zero_entry(queue_name, channel))
        for metric in collection.get("Collections", []):
            name = metric["Metric"]["Name"]
            value = int(metric.get("Value", 0) or 0)
            if name == "CONTACTS_IN_QUEUE":
                entry["contactsInQueue"] = value
            elif name == "OLDEST_CONTACT_AGE":
                entry["oldestContactAgeSeconds"] = value
            elif name == "AGENTS_AVAILABLE":
                entry["agentsAvailable"] = value
            elif name == "AGENTS_ON_CONTACT":
                entry["agentsOnContact"] = value
            elif name == "AGENTS_AFTER_CONTACT_WORK":
                entry["agentsAfterContactWork"] = value

    # Always return all three expected combos — fill missing with zeros
    expected = [
        ("SupportQueue", "VOICE"),
        ("SupportQueue", "CHAT"),
        ("BillingQueue", "VOICE"),
    ]
    queues = []
    for queue_name, channel in expected:
        queues.append(result_map.get((queue_name, channel), _zero_entry(queue_name, channel)))

    as_of = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    return {"queues": queues, "asOf": as_of}


def _zero_entry(queue_name, channel):
    return {
        "queueName": queue_name,
        "channel": channel,
        "contactsInQueue": 0,
        "oldestContactAgeSeconds": 0,
        "agentsAvailable": 0,
        "agentsOnContact": 0,
        "agentsAfterContactWork": 0,
    }


def _empty_queues_response():
    as_of = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    queues = [
        _zero_entry("SupportQueue", "VOICE"),
        _zero_entry("SupportQueue", "CHAT"),
        _zero_entry("BillingQueue", "VOICE"),
    ]
    return {"queues": queues, "asOf": as_of}


def _format_contact(c):
    return {
        "contactId": c.get("contactId", ""),
        "timestamp": c.get("timestamp", ""),
        "channel": c.get("channel", ""),
        "sentiment": c.get("sentiment", ""),
        "sentimentScore": float(c.get("sentimentScore", 0)),
        "duration": int(c.get("duration", 0)),
        "queue": c.get("queueName", ""),
        "agentId": c.get("agentId", ""),
    }


def handler(event, context):
    method = event.get("httpMethod", "GET")
    path = event.get("path", "")

    log(logging.INFO, "request received", method=method, path=path)

    # OPTIONS preflight for CORS
    if method == "OPTIONS":
        return _response(200, {})

    try:
        if path == "/contacts" and method == "GET":
            items = _get_contacts()
            contacts = [_format_contact(c) for c in items]
            return _response(200, {"contacts": contacts, "total": len(contacts)})

        elif path == "/contacts/flagged" and method == "GET":
            items = _get_flagged()
            contacts = [_format_contact(c) for c in items]
            return _response(200, {"contacts": contacts, "total": len(contacts)})

        elif path == "/metrics" and method == "GET":
            metrics = _get_metrics()
            return _response(200, metrics)

        elif path == "/queues/live" and method == "GET":
            data = _get_queues_live()
            return _response(200, data)

        else:
            return _response(404, {"error": "Not found"})

    except Exception as e:
        log(logging.ERROR, "unhandled exception", path=path, error=str(e))
        return _response(500, {"error": "Internal server error"})
