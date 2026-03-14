"""
deploy_flows.py
Pushes contact flow JSON updates to Amazon Connect without a full terraform apply.
Reads the Name field from inside each flow JSON — does not infer names from filenames.

Usage:
    python deploy_flows.py --instance-id <id> --flow-dir connect/flows --region us-east-1

TODO: implement in Phase 6
"""
import argparse


def main():
    parser = argparse.ArgumentParser(description="Push Connect flow JSON updates")
    parser.add_argument("--instance-id", required=True)
    parser.add_argument("--flow-dir",    default="connect/flows")
    parser.add_argument("--region",      default="us-east-1")
    args = parser.parse_args()
    print(f"TODO: deploy flows from {args.flow_dir} to instance {args.instance_id}")


if __name__ == "__main__":
    main()
