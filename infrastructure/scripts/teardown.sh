#!/usr/bin/env bash
# teardown.sh
# Safe teardown — two modes:
#
#   Default (full destroy):
#     Releases phone numbers, empties S3 buckets, runs terraform destroy.
#     terraform destroy fails if phone numbers or non-empty buckets remain —
#     this script handles both before running destroy.
#
#   --data-only (demo reset, no infrastructure changes):
#     Clears DynamoDB contacts/flagged tables and re-seeds orders.
#     Use between demo sessions to reset to a clean state without touching
#     the Connect instance, phone number, or any AWS infrastructure.
#     The Connect instance has no standing charge — there is no cost reason
#     to run a full teardown between demos.
#
# Usage:
#   ./infrastructure/scripts/teardown.sh [--data-only] [--region REGION]
#
# Flags:
#   --data-only  Reset DynamoDB data only — do not destroy infrastructure
#   --region     AWS region (default: us-east-1)

set -euo pipefail

REGION="us-east-1"
DATA_ONLY=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --data-only) DATA_ONLY=true; shift ;;
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Data-only reset ───────────────────────────────────────────────────────────
if [[ "${DATA_ONLY}" == "true" ]]; then
  echo "==> SmartCX Data Reset (region: ${REGION})"
  echo ""
  echo "    This will clear the contacts and flagged tables, then re-seed orders."
  echo -n "    Continue? [y/N] "
  read -r confirm
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "    Aborted."
    exit 0
  fi

  cd "${TF_DIR}"
  ORDERS_TABLE=$(terraform output -raw orders_table_name 2>/dev/null || echo "")
  CONTACTS_TABLE=$(terraform output -raw contacts_table_name 2>/dev/null || echo "")
  FLAGGED_TABLE=$(terraform output -raw flagged_table_name 2>/dev/null || echo "")

  if [[ -z "${ORDERS_TABLE}" ]]; then
    echo "    ERROR: Could not read Terraform outputs — is the stack deployed?"
    exit 1
  fi

  echo ""
  echo "==> [1/3] Clearing contacts table (${CONTACTS_TABLE})"
  # Scan for all contactIds, then batch-delete
  CONTACT_KEYS=$(aws dynamodb scan \
    --table-name "${CONTACTS_TABLE}" \
    --region "${REGION}" \
    --projection-expression "contactId" \
    --query "Items[].contactId.S" \
    --output text 2>/dev/null || echo "")
  if [[ -z "${CONTACT_KEYS}" || "${CONTACT_KEYS}" == "None" ]]; then
    echo "    Table already empty — skipping"
  else
    for key in ${CONTACT_KEYS}; do
      aws dynamodb delete-item \
        --table-name "${CONTACTS_TABLE}" \
        --key "{\"contactId\": {\"S\": \"${key}\"}}" \
        --region "${REGION}" > /dev/null
    done
    echo "    Cleared $(echo "${CONTACT_KEYS}" | wc -w | tr -d ' ') records"
  fi

  echo ""
  echo "==> [2/3] Clearing flagged-contacts table (${FLAGGED_TABLE})"
  FLAGGED_KEYS=$(aws dynamodb scan \
    --table-name "${FLAGGED_TABLE}" \
    --region "${REGION}" \
    --projection-expression "contactId" \
    --query "Items[].contactId.S" \
    --output text 2>/dev/null || echo "")
  if [[ -z "${FLAGGED_KEYS}" || "${FLAGGED_KEYS}" == "None" ]]; then
    echo "    Table already empty — skipping"
  else
    for key in ${FLAGGED_KEYS}; do
      aws dynamodb delete-item \
        --table-name "${FLAGGED_TABLE}" \
        --key "{\"contactId\": {\"S\": \"${key}\"}}" \
        --region "${REGION}" > /dev/null
    done
    echo "    Cleared $(echo "${FLAGGED_KEYS}" | wc -w | tr -d ' ') records"
  fi

  echo ""
  echo "==> [3/3] Re-seeding orders table (${ORDERS_TABLE})"
  cd "${REPO_ROOT}"
  python infrastructure/scripts/seed_dynamodb.py \
    --table "${ORDERS_TABLE}" \
    --region "${REGION}"

  echo ""
  echo "============================================================"
  echo "  SmartCX Data Reset Complete"
  echo "============================================================"
  echo "  Contacts and flagged tables cleared."
  echo "  Orders table re-seeded with demo data."
  echo "  Infrastructure unchanged — Connect instance still running."
  echo "============================================================"
  exit 0
fi

echo "==> SmartCX Full Teardown (region: ${REGION})"
echo ""
echo "    WARNING: This will destroy ALL SmartCX Demo infrastructure."
echo "    To reset demo data only (no infrastructure changes), use --data-only."
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

# ── Step 2: Release phone numbers ─────────────────────────────────────────────
if [[ -n "${INSTANCE_ID}" ]]; then
  echo ""
  echo "==> [2/4] Releasing phone numbers from Connect instance"

  # list-phone-numbers-v2 returns all numbers; filter to this instance via target-arn
  INSTANCE_ARN=$(aws connect describe-instance \
    --instance-id "${INSTANCE_ID}" \
    --region "${REGION}" \
    --query 'Instance.Arn' \
    --output text 2>/dev/null || echo "")

  PHONE_NUMBER_IDS=""
  if [[ -n "${INSTANCE_ARN}" ]]; then
    PHONE_NUMBER_IDS=$(aws connect list-phone-numbers-v2 \
      --target-arn "${INSTANCE_ARN}" \
      --region "${REGION}" \
      --query 'ListedPhoneNumbers[].PhoneNumberId' \
      --output text 2>/dev/null || echo "")
  fi

  # Guard against AWS CLI returning the literal string "None"
  if [[ -z "${PHONE_NUMBER_IDS}" || "${PHONE_NUMBER_IDS}" == "None" ]]; then
    echo "    No phone numbers claimed — skipping"
  else
    for phone_id in ${PHONE_NUMBER_IDS}; do
      echo "    Releasing phone number: ${phone_id}"
      aws connect release-phone-number \
        --phone-number-id "${phone_id}" \
        --region "${REGION}"

      # Poll until release completes
      echo -n "    Waiting for release"
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
echo "  The Lex v2 bot SmartCXOrderBot is managed by Terraform"
echo "  and has been destroyed above."
echo "============================================================"
