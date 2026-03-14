#!/usr/bin/env bash
# teardown.sh
# Safe teardown: disassociates phone numbers, empties S3 buckets,
# then runs terraform destroy.
# terraform destroy fails if phone numbers are still associated or S3 buckets are non-empty.
#
# Usage:
#   ./infrastructure/scripts/teardown.sh [--region us-east-1]
#
# TODO: implement in Phase 6
set -euo pipefail

echo "TODO: implement teardown.sh in Phase 6"
