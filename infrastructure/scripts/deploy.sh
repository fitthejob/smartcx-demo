#!/usr/bin/env bash
# deploy.sh
# Full deploy: packages Lambda deps, applies Terraform, enables flow logs,
# associates Lex v2 bot, builds and uploads the React dashboard,
# optionally seeds DynamoDB, and runs post-deploy validation.
#
# Usage:
#   ./infrastructure/scripts/deploy.sh [--seed] [--region REGION]
#
# Flags:
#   --seed      Also seed the DynamoDB orders table with demo data
#   --region    AWS region (default: us-east-1)
#
# Prerequisites:
#   - terraform.tfvars populated (project_name, agent_password, admin_email, alert_email)
#   - AWS CLI configured with sufficient permissions
#   - Python 3.12, Node.js 20+, Terraform >= 1.6 on PATH

set -euo pipefail

REGION="us-east-1"
SEED=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TF_DIR="${REPO_ROOT}/infrastructure/terraform"

# ── Parse args ────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --seed)   SEED=true; shift ;;
    --region) REGION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

echo "==> SmartCX Deploy (region: ${REGION})"

# ── Step 1: Package Lambda dependencies ───────────────────────────────────────
echo ""
echo "==> [1/8] Packaging Lambda dependencies"
for fn_dir in "${REPO_ROOT}"/lambda/*/; do
  fn_name=$(basename "${fn_dir}")
  req="${fn_dir}requirements.txt"
  if [[ -f "${req}" ]]; then
    echo "    Installing deps for ${fn_name}"
    pip install -r "${req}" -t "${fn_dir}package/" --quiet --upgrade
  else
    echo "    No requirements.txt for ${fn_name} — skipping"
  fi
done

# ── Step 2: Terraform init + apply ────────────────────────────────────────────
echo ""
echo "==> [2/8] Running terraform init + apply"
cd "${TF_DIR}"
terraform init -input=false
terraform apply -auto-approve -input=false

# ── Step 3: Read Terraform outputs ────────────────────────────────────────────
echo ""
echo "==> [3/8] Reading Terraform outputs"
INSTANCE_ID=$(terraform output -raw connect_instance_id)
LEX_BOT_ID=$(terraform output -raw lex_bot_id)
API_ENDPOINT=$(terraform output -raw api_endpoint)
BUCKET_NAME=$(terraform output -raw bucket_name)
DISTRIBUTION_ID=$(terraform output -raw distribution_id)
ORDERS_TABLE=$(terraform output -raw orders_table_name)
DLQ_URL=$(terraform output -raw contact_lens_dlq_url)
DASHBOARD_URL=$(terraform output -raw dashboard_url)
COGNITO_USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
COGNITO_CLIENT_ID=$(terraform output -raw cognito_client_id)
COGNITO_REGION=$(terraform output -raw cognito_region)

# Construct the Lex alias ARN from its parts.
# Neither list-bot-aliases nor describe-bot-alias returns an ARN field —
# the ARN must be built from: region, account ID, bot ID, and alias ID.
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LEX_ALIAS_ID=$(aws lexv2-models list-bot-aliases \
  --bot-id "${LEX_BOT_ID}" \
  --region "${REGION}" \
  --query "botAliasSummaries[?botAliasName=='live'].botAliasId | [0]" \
  --output text)
LEX_ALIAS_ARN="arn:aws:lex:${REGION}:${ACCOUNT_ID}:bot-alias/${LEX_BOT_ID}/${LEX_ALIAS_ID}"

echo "    Connect instance:  ${INSTANCE_ID}"
echo "    API endpoint:      ${API_ENDPOINT}"
echo "    Dashboard bucket:  ${BUCKET_NAME}"
echo "    Lex alias ARN:     ${LEX_ALIAS_ARN}"
echo "    Cognito pool:      ${COGNITO_USER_POOL_ID}"

# ── Step 4: Post-apply Connect configuration ──────────────────────────────────
echo ""
echo "==> [4/8] Enabling contact flow logs"
aws connect update-instance-attribute \
  --instance-id "${INSTANCE_ID}" \
  --attribute-type CONTACTFLOW_LOGS \
  --value true \
  --region "${REGION}"

echo "==> [4/8] Associating Lex v2 bot with Connect"
# associate-lex-bot is Lex v1 only. associate-bot supports both v1 and v2.
# --lex-v2-bot takes a JSON object with aliasArn key.
aws connect associate-bot \
  --instance-id "${INSTANCE_ID}" \
  --lex-v2-bot "AliasArn=${LEX_ALIAS_ARN}" \
  --region "${REGION}"

# ── Step 5: Build dashboard ───────────────────────────────────────────────────
echo ""
echo "==> [5/8] Building React dashboard"
cd "${REPO_ROOT}/dashboard"
cat > .env <<ENV
VITE_API_BASE_URL=${API_ENDPOINT}
VITE_COGNITO_USER_POOL_ID=${COGNITO_USER_POOL_ID}
VITE_COGNITO_CLIENT_ID=${COGNITO_CLIENT_ID}
VITE_COGNITO_REGION=${COGNITO_REGION}
ENV
npm install
npm run build

# ── Step 6: Deploy dashboard to S3 + invalidate CloudFront ───────────────────
echo ""
echo "==> [6/8] Uploading dashboard to S3"
aws s3 sync dist/ "s3://${BUCKET_NAME}" \
  --delete \
  --region "${REGION}" \
  --cache-control "no-cache" \
  --exclude ".DS_Store"

echo "==> [6/8] Invalidating CloudFront cache"
aws cloudfront create-invalidation \
  --distribution-id "${DISTRIBUTION_ID}" \
  --paths "/*" \
  --output text --query 'Invalidation.Id'

# ── Step 7: Optional DynamoDB seed ───────────────────────────────────────────
if [[ "${SEED}" == "true" ]]; then
  echo ""
  echo "==> [7/8] Seeding DynamoDB orders table"
  cd "${REPO_ROOT}"
  python infrastructure/scripts/seed_dynamodb.py \
    --table "${ORDERS_TABLE}" \
    --region "${REGION}"
else
  echo ""
  echo "==> [7/8] Skipping DynamoDB seed (pass --seed to enable)"
fi

# ── Step 8: Post-deploy validation ───────────────────────────────────────────
echo ""
echo "==> [8/8] Running post-deploy validation"
cd "${REPO_ROOT}"
python infrastructure/scripts/validate_connect.py \
  --instance-id "${INSTANCE_ID}" \
  --dlq-url "${DLQ_URL}" \
  --region "${REGION}"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "  SmartCX Deploy Complete"
echo "============================================================"
echo "  Dashboard: ${DASHBOARD_URL}"
echo "  API:       ${API_ENDPOINT}"
echo "  Connect:   https://${INSTANCE_ID}.my.connect.aws/ccp-v2/"
echo ""
echo "  Next manual steps:"
echo "  1. Claim a phone number in the Connect console and"
echo "     associate it with MainIVRFlow"
echo "  2. Sign in to the dashboard — you will be prompted to"
echo "     set a permanent password on first login"
echo "     (see docs/setup-guide.md for details)"
echo "============================================================"
