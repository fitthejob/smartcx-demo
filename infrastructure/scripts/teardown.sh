#!/usr/bin/env bash
# teardown.sh
# Safe teardown — must run before terraform destroy.
#
# terraform destroy fails if:
#   - A phone number is still associated with the Connect instance
#   - S3 buckets are non-empty (recordings, dashboard)
#
# This script handles both before running destroy.
#
# Usage:
#   ./infrastructure/scripts/teardown.sh [--region REGION]
#
# Flags:
#   --region    AWS region (default: us-east-1)

set -euo pipefail

REGION="us-east-1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

echo "==> SmartCX Teardown (region: ${REGION})"
echo ""
echo "    WARNING: This will destroy all SmartCX Demo infrastructure."
echo -n "    Continue? [y/N] "
read -r confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "    Aborted."
  exit 0
fi

# ── Read Terraform outputs ────────────────────────────────────────────────────
echo ""
echo "==> [1/4] Reading Terraform outputs"
cd "${TF_DIR}"
INSTANCE_ID=$(terraform output -raw connect_instance_id 2>/dev/null || echo "")
RECORDINGS_BUCKET=$(terraform output -raw recordings_bucket_name 2>/dev/null || echo "")
DASHBOARD_BUCKET=$(terraform output -raw bucket_name 2>/dev/null || echo "")

if [[ -z "${INSTANCE_ID}" ]]; then
  echo "    No connect_instance_id output — stack may already be destroyed."
  echo "    Running terraform destroy anyway to clean up any remaining state."
else
  echo "    Connect instance: ${INSTANCE_ID}"
fi

# ── Step 2: Disassociate phone numbers ────────────────────────────────────────
if [[ -n "${INSTANCE_ID}" ]]; then
  echo ""
  echo "==> [2/4] Disassociating phone numbers from Connect instance"

  PHONE_NUMBER_IDS=$(aws connect list-phone-numbers-v2 \
    --instance-id "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'ListedPhoneNumbers[].PhoneNumberId' \
    --output text 2>/dev/null || echo "")

  if [[ -z "${PHONE_NUMBER_IDS}" ]]; then
    echo "    No phone numbers associated — skipping"
  else
    for phone_id in ${PHONE_NUMBER_IDS}; do
      echo "    Disassociating phone number: ${phone_id}"
      aws connect disassociate-phone-number \
        --phone-number-id "${phone_id}" \
        --region "${REGION}"

      # Poll until disassociation completes
      echo -n "    Waiting for disassociation"
      for _ in $(seq 1 30); do
        STATUS=$(aws connect describe-phone-number \
          --phone-number-id "${phone_id}" \
          --region "${REGION}" \
          --query 'ClaimedPhoneNumberSummary.PhoneNumberStatus.Status' \
          --output text 2>/dev/null || echo "RELEASED")
        if [[ "${STATUS}" != "IN_PROGRESS" ]]; then
          echo " done (${STATUS})"
          break
        fi
        echo -n "."
        sleep 3
      done
    done
  fi
fi

# ── Step 3: Empty S3 buckets ──────────────────────────────────────────────────
echo ""
echo "==> [3/4] Emptying S3 buckets"

for bucket in "${RECORDINGS_BUCKET}" "${DASHBOARD_BUCKET}"; do
  if [[ -z "${bucket}" ]]; then
    continue
  fi
  echo "    Emptying s3://${bucket}"
  aws s3 rm "s3://${bucket}" --recursive --region "${REGION}" 2>/dev/null || \
    echo "    Bucket empty or does not exist — skipping"
done

# ── Step 4: Terraform destroy ─────────────────────────────────────────────────
echo ""
echo "==> [4/4] Running terraform destroy"
cd "${TF_DIR}"
terraform destroy -auto-approve -input=false

echo ""
echo "============================================================"
echo "  SmartCX Teardown Complete"
echo "============================================================"
echo "  All infrastructure destroyed."
echo "  Note: The Lex v2 bot SmartCXOrderBot must be deleted"
echo "  manually in the Amazon Lex console — it was created"
echo "  manually and is not managed by Terraform."
echo "============================================================"
