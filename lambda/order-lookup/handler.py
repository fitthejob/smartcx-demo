"""
order-lookup Lambda
Triggered by Amazon Connect contact flow (Invoke AWS Lambda block).
Looks up an order by orderId or by caller phone number (ANI) via GSI.

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
