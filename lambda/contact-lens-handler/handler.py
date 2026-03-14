"""
contact-lens-handler Lambda
Triggered by EventBridge on Contact Lens Analysis State Change (SUCCEEDED).
Writes contact records to DynamoDB and publishes SNS alerts for negative sentiment.

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
