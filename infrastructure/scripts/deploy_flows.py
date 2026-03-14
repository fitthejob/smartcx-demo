"""
deploy_flows.py
Pushes contact flow JSON updates to Amazon Connect without a full terraform apply.
Useful during flow iteration — edit the JSON, run this script, test immediately.

Flow names are read from the Name field inside each JSON file, not inferred from
filenames. This matches how Connect exports flows and prevents silent mismatches
if a filename and the flow's display name diverge.

Usage:
    python deploy_flows.py --instance-id <id> [--flow-dir connect/flows] [--region us-east-1]

Exit codes:
    0 — all flows updated successfully
    1 — one or more flows failed to update
"""
import argparse
import json
import sys
from pathlib import Path

import boto3
from botocore.exceptions import ClientError


def load_flows(flow_dir: Path) -> list[tuple[str, str]]:
    """Return list of (flow_name, raw_json_string) for each *.json in flow_dir."""
    flows = []
    for path in sorted(flow_dir.glob("*.json")):
        raw = path.read_text(encoding="utf-8")
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as e:
            print(f"  [ERROR] {path.name}: invalid JSON — {e}")
            continue
        name = parsed.get("Name")
        if not name:
            print(f"  [SKIP]  {path.name}: no 'Name' field in JSON")
            continue
        flows.append((name, raw))
    return flows


def get_flow_id(client, instance_id: str, flow_name: str) -> str | None:
    """Return the ContactFlowId for a flow matching flow_name, or None."""
    paginator = client.get_paginator("list_contact_flows")
    for page in paginator.paginate(InstanceId=instance_id):
        for flow in page.get("ContactFlowSummaryList", []):
            if flow["Name"] == flow_name:
                return flow["Id"]
    return None


def main():
    parser = argparse.ArgumentParser(
        description="Push Connect flow JSON updates without a full terraform apply"
    )
    parser.add_argument("--instance-id", required=True, help="Connect instance ID")
    parser.add_argument("--flow-dir",    default="connect/flows", help="Directory containing flow JSON files")
    parser.add_argument("--region",      default="us-east-1")
    args = parser.parse_args()

    flow_dir = Path(args.flow_dir)
    if not flow_dir.is_dir():
        print(f"ERROR: flow directory not found: {flow_dir}")
        sys.exit(1)

    client = boto3.client("connect", region_name=args.region)
    flows = load_flows(flow_dir)

    if not flows:
        print("No flow JSON files found.")
        sys.exit(0)

    print(f"Deploying {len(flows)} flow(s) to instance {args.instance_id}")
    print()

    failures = 0
    for flow_name, content in flows:
        flow_id = get_flow_id(client, args.instance_id, flow_name)
        if not flow_id:
            print(f"  [FAIL]  {flow_name}: flow not found in instance — has it been created yet?")
            failures += 1
            continue

        try:
            client.update_contact_flow_content(
                InstanceId=args.instance_id,
                ContactFlowId=flow_id,
                Content=content,
            )
            print(f"  [OK]    {flow_name} ({flow_id})")
        except ClientError as e:
            print(f"  [FAIL]  {flow_name}: {e.response['Error']['Code']} — {e.response['Error']['Message']}")
            failures += 1

    print()
    if failures:
        print(f"  {failures} flow(s) failed. Check errors above.")
        sys.exit(1)
    else:
        print(f"  All {len(flows)} flow(s) updated successfully.")


if __name__ == "__main__":
    main()
