"""
dashboard-api Lambda
Triggered by API Gateway.
Serves /contacts, /contacts/flagged, /metrics, and /queues/live.

TODO: implement in Phase 2
"""
import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)


def log(level, msg, **kwargs):
    logger.log(level, json.dumps({"level": logging.getLevelName(level), "msg": msg, **kwargs}))


def handler(event, context):
    pass
