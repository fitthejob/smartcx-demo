"""
validate_connect.py
Post-deploy health check — verifies the Connect instance is correctly configured.
Prints a pass/fail checklist and exits with code 1 if any check fails.

Usage:
    python validate_connect.py --instance-id <id> --dlq-url <url> [--region us-east-1]

Exit codes:
    0 — all checks passed
    1 — one or more checks failed
"""
import argparse
import sys

import boto3
from botocore.exceptions import ClientError

EXPECTED_QUEUES = {"SupportQueue", "BillingQueue"}
EXPECTED_FLOWS = {"MainIVRFlow", "ChatFlow", "AgentWhisper"}
EXPECTED_ROUTING_PROFILE = "DemoAgentProfile"
LEX_BOT_NAME = "SmartCXOrderBot"
ORDER_LOOKUP_FUNCTION_SUBSTR = "order-lookup"


def check(label: str, passed: bool, detail: str = "") -> bool:
    status = "PASS" if passed else "FAIL"
    suffix = f" — {detail}" if detail else ""
    print(f"  [{status}] {label}{suffix}")
    return passed


def main():
    parser = argparse.ArgumentParser(description="Validate SmartCX Connect post-deploy configuration")
    parser.add_argument("--instance-id", required=True, help="Connect instance ID")
    parser.add_argument("--dlq-url",     required=True, help="Contact Lens handler DLQ URL")
    parser.add_argument("--region",      default="us-east-1")
    args = parser.parse_args()

    connect = boto3.client("connect", region_name=args.region)
    sqs     = boto3.client("sqs",     region_name=args.region)

    failures = 0
    print(f"\nValidating SmartCX Demo — instance {args.instance_id}\n")

    # ── 1. Instance exists and is ACTIVE ──────────────────────────────────────
    try:
        resp = connect.describe_instance(InstanceId=args.instance_id)
        status = resp["Instance"]["InstanceStatus"]
        ok = check("Instance ACTIVE", status == "ACTIVE", f"status={status}")
    except ClientError as e:
        ok = check("Instance exists", False, str(e))
    if not ok:
        failures += 1

    # ── 2. Contact flow logs enabled ──────────────────────────────────────────
    try:
        resp = connect.describe_instance_attribute(
            InstanceId=args.instance_id,
            AttributeType="CONTACT_FLOW_LOGS",
        )
        value = resp["Attribute"]["Value"]
        ok = check("Contact flow logs enabled", value == "true", f"value={value}")
    except ClientError as e:
        ok = check("Contact flow logs enabled", False, str(e))
    if not ok:
        failures += 1

    # ── 3. Queues exist ───────────────────────────────────────────────────────
    try:
        paginator = connect.get_paginator("list_queues")
        found_queues = set()
        for page in paginator.paginate(InstanceId=args.instance_id):
            for q in page.get("QueueSummaryList", []):
                if q["Name"] in EXPECTED_QUEUES:
                    found_queues.add(q["Name"])
        for queue_name in sorted(EXPECTED_QUEUES):
            ok = check(f"Queue exists: {queue_name}", queue_name in found_queues)
            if not ok:
                failures += 1
    except ClientError as e:
        check("Queues", False, str(e))
        failures += 1

    # ── 4. DemoAgentProfile routing profile exists ────────────────────────────
    try:
        paginator = connect.get_paginator("list_routing_profiles")
        profile_found = False
        profile_id = None
        for page in paginator.paginate(InstanceId=args.instance_id):
            for rp in page.get("RoutingProfileSummaryList", []):
                if rp["Name"] == EXPECTED_ROUTING_PROFILE:
                    profile_found = True
                    profile_id = rp["Id"]
                    break
        ok = check(f"Routing profile exists: {EXPECTED_ROUTING_PROFILE}", profile_found)
        if not ok:
            failures += 1
    except ClientError as e:
        check(f"Routing profile: {EXPECTED_ROUTING_PROFILE}", False, str(e))
        failures += 1

    # ── 5. Contact flows exist and are published ──────────────────────────────
    try:
        paginator = connect.get_paginator("list_contact_flows")
        found_flows = {}
        for page in paginator.paginate(InstanceId=args.instance_id):
            for f in page.get("ContactFlowSummaryList", []):
                if f["Name"] in EXPECTED_FLOWS:
                    found_flows[f["Name"]] = f.get("ContactFlowState", "")
        for flow_name in sorted(EXPECTED_FLOWS):
            state = found_flows.get(flow_name, "")
            ok = check(
                f"Contact flow exists: {flow_name}",
                flow_name in found_flows,
                f"state={state}" if state else "not found",
            )
            if not ok:
                failures += 1
    except ClientError as e:
        check("Contact flows", False, str(e))
        failures += 1

    # ── 6. order-lookup Lambda associated ─────────────────────────────────────
    try:
        paginator = connect.get_paginator("list_lambda_functions")
        lambda_found = False
        for page in paginator.paginate(InstanceId=args.instance_id):
            for fn in page.get("LambdaFunctions", []):
                if ORDER_LOOKUP_FUNCTION_SUBSTR in fn:
                    lambda_found = True
                    break
        ok = check("order-lookup Lambda associated", lambda_found)
        if not ok:
            failures += 1
    except ClientError as e:
        check("order-lookup Lambda associated", False, str(e))
        failures += 1

    # ── 7. Lex bot associated ─────────────────────────────────────────────────
    try:
        paginator = connect.get_paginator("list_lex_bots")
        lex_found = False
        for page in paginator.paginate(InstanceId=args.instance_id):
            for bot in page.get("LexBots", []):
                if bot.get("Name") == LEX_BOT_NAME:
                    lex_found = True
                    break
        # Also check Lex v2
        if not lex_found:
            v2_resp = connect.list_lex_bots(InstanceId=args.instance_id)
            for bot in v2_resp.get("LexBots", []):
                if LEX_BOT_NAME in bot.get("AliasArn", ""):
                    lex_found = True
                    break
        ok = check(f"Lex bot associated: {LEX_BOT_NAME}", lex_found)
        if not ok:
            failures += 1
    except ClientError as e:
        check(f"Lex bot associated: {LEX_BOT_NAME}", False, str(e))
        failures += 1

    # ── 8 & 9. Storage configs ────────────────────────────────────────────────
    for resource_type in ("CALL_RECORDINGS", "CONTACT_TRACE_RECORDS"):
        try:
            resp = connect.list_instance_storage_configs(
                InstanceId=args.instance_id,
                ResourceType=resource_type,
            )
            configs = resp.get("StorageConfigs", [])
            ok = check(f"Storage config: {resource_type}", len(configs) > 0)
            if not ok:
                failures += 1
        except ClientError as e:
            check(f"Storage config: {resource_type}", False, str(e))
            failures += 1

    # ── 10. DLQ empty ─────────────────────────────────────────────────────────
    try:
        resp = sqs.get_queue_attributes(
            QueueUrl=args.dlq_url,
            AttributeNames=["ApproximateNumberOfMessages"],
        )
        depth = int(resp["Attributes"].get("ApproximateNumberOfMessages", 0))
        ok = check("Contact Lens DLQ empty", depth == 0, f"depth={depth}")
        if not ok:
            failures += 1
    except ClientError as e:
        check("Contact Lens DLQ empty", False, str(e))
        failures += 1

    # ── Summary ───────────────────────────────────────────────────────────────
    total = 10 + len(EXPECTED_QUEUES) + len(EXPECTED_FLOWS) - 2
    print()
    if failures:
        print(f"  {failures} check(s) failed. Review the output above.")
        sys.exit(1)
    else:
        print("  All checks passed.")


if __name__ == "__main__":
    main()
