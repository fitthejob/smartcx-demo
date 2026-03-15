# SmartCX Demo — Setup Guide

End-to-end instructions for deploying the SmartCX Demo stack from scratch on a clean AWS account.

---

## Step 1 — Prerequisites

Install and configure the following before proceeding.

| Tool | Version | Notes |
|---|---|---|
| AWS CLI | v2 | `aws --version` |
| Terraform | >= 1.6 | `terraform -version` |
| Python | 3.12 | `python --version` |
| Node.js | 20+ | `node --version` |

**AWS credentials:**
```bash
aws configure
# Enter: Access Key ID, Secret Access Key, default region (us-east-1), output format (json)
```

Verify access:
```bash
aws sts get-caller-identity
```

**Required IAM permissions** — the deploying identity needs permissions across:
Connect, Lex, Lambda, DynamoDB, API Gateway, EventBridge, SNS, SQS, S3, CloudFront, CloudWatch, IAM (role/policy creation).

For a personal AWS account, `AdministratorAccess` is simplest. For a shared account, scope to the services above.

---

## Step 2 — Configure Terraform Variables

Copy the example file and fill in your values:

```bash
cd infrastructure/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region          = "us-east-1"
project_name        = "smartcx-demo"
alert_email         = "your-email@example.com"   # receives negative-sentiment SNS alerts
sentiment_threshold = "-0.5"
agent_password      = "YourPassword1!"           # see password policy below
```

**Connect password policy** — `agent_password` must meet all of:
- 8 or more characters
- At least one uppercase letter
- At least one lowercase letter
- At least one number
- At least one special character (e.g. `!`, `@`, `#`)

> `terraform.tfvars` is excluded by `.gitignore` — never commit it. The committed template is `terraform.tfvars.example`.

---

## Step 4 — Terraform Init and Apply

```bash
cd infrastructure/terraform
terraform init
terraform plan    # review — expect ~35 new resources on first full apply
terraform apply
```

After apply, capture the outputs:
```bash
terraform output
```

Key outputs:

| Output | Used for |
|---|---|
| `connect_instance_id` | Post-apply CLI commands |
| `api_endpoint` | Dashboard `VITE_API_BASE_URL` env var |
| `dashboard_url` | CloudFront URL for the dashboard |
| `bucket_name` | S3 bucket for dashboard static build |
| `distribution_id` | CloudFront invalidation after dashboard deploy |
| `main_ivr_flow_id` | Reference — MainIVRFlow contact flow ID |

**What Terraform provisions:**
- Lex v2 bot (`SmartCXOrderBot`) with `CheckOrderStatus` and `CancelOrder` intents, published version, and `live` alias
- Connect instance, hours of operation, queues (`SupportQueue`, `BillingQueue`), routing profiles (`DemoAgentProfile`, `BillingAgentProfile`)
- Contact flows: `MainIVRFlow`, `ChatFlow`, `AgentWhisper`
- Agent users: `demo-agent` (DemoAgentProfile) and `billing-agent` (BillingAgentProfile)
- Lambda functions, DynamoDB tables, API Gateway, EventBridge rule, SNS topic, SQS DLQ, S3 buckets, CloudFront distribution, CloudWatch alarms

### 4.1 Agent users

`demo-agent` and `billing-agent` are fully managed by Terraform. They are created on apply and destroyed on destroy — no manual user creation is needed.

Both users are created with:
- Security profile: `Agent`
- Phone type: `SOFT_PHONE`
- Password: the value of `agent_password` in `terraform.tfvars`

To log in as an agent after apply:
```
https://<instance-alias>.my.connect.aws/ccp-v2/
```
Where `<instance-alias>` matches `project_name` in `terraform.tfvars` (default: `smartcx-demo`).

---

## Step 4.2 — Enable Contact Flow Logs

Contact flow logging is an instance-level attribute, not a flow-level setting, and is not managed by Terraform. Run once after apply:

```bash
aws connect update-instance-attribute \
  --instance-id $(cd infrastructure/terraform && terraform output -raw connect_instance_id) \
  --attribute-type CONTACTFLOW_LOGS \
  --value true \
  --region us-east-1
```

> Note: the attribute type is `CONTACTFLOW_LOGS` — no underscore between CONTACT and FLOW.

---

## Step 5 — Claim a Phone Number

Phone number claiming has no Terraform or CLI support — it must be done in the Connect console.

1. Connect console → **Channels** → **Phone numbers** → **Claim a number**
2. Type: DID (local) or Toll-free, Country: US
3. Associate with flow: `MainIVRFlow`
4. Note the number — all test calls use this number

---

## Step 6 — Seed DynamoDB with Demo Orders

The seed script populates `smartcx-demo-orders` with 22 sample orders keyed by phone number so the order-lookup Lambda has data to return during test calls.

**Option A — seed as part of deploy (recommended for first deploy):**
```bash
./infrastructure/scripts/deploy.sh --seed
```

**Option B — seed standalone (re-seed without redeploying):**
```bash
python infrastructure/scripts/seed_dynamodb.py \
  --table smartcx-demo-orders \
  --region us-east-1
```

**Option C — full data reset between demo sessions:**
```bash
./infrastructure/scripts/teardown.sh --data-only
```
Clears contacts and flagged-contacts tables, then re-seeds orders. Infrastructure untouched.

The seed data uses phone numbers in the `+1616555010x` range. Call from one of those numbers to trigger an ANI-based order lookup, or press `1` and provide an order ID manually.

---

## Step 7 — Build and Deploy the React Dashboard

```bash
cd dashboard
cp .env.example .env       # if .env does not exist
```

Edit `dashboard/.env`:
```
VITE_API_BASE_URL=https://YOUR_API_GATEWAY_URL/prod
```

Use the `api_endpoint` value from `terraform output`.

```bash
npm install
npm run build
```

Deploy to S3 and invalidate CloudFront:
```bash
BUCKET=$(cd ../infrastructure/terraform && terraform output -raw bucket_name)
DIST_ID=$(cd ../infrastructure/terraform && terraform output -raw distribution_id)

aws s3 sync dist/ s3://$BUCKET --delete
aws cloudfront create-invalidation --distribution-id $DIST_ID --paths "/*"
```

The dashboard URL is available at:
```bash
cd infrastructure/terraform && terraform output -raw dashboard_url
```

---

## Step 8 — Post-Deploy Validation

Run the smoke-test script to verify all resources are correctly configured:

```bash
cd infrastructure/scripts

INSTANCE_ID=$(cd ../terraform && terraform output -raw connect_instance_id)
DLQ_URL=$(cd ../terraform && terraform output -raw contact_lens_dlq_url)

python validate_connect.py \
  --instance-id $INSTANCE_ID \
  --dlq-url $DLQ_URL \
  --region us-east-1
```

The script checks:
1. Instance is `ACTIVE`
2. Contact flow logs enabled
3. `SupportQueue` and `BillingQueue` exist
4. `DemoAgentProfile` routing profile exists
5. `MainIVRFlow`, `ChatFlow`, `AgentWhisper` flows exist
6. `order-lookup` Lambda is associated
7. Lex bot is associated
8. `CALL_RECORDINGS` storage config present
9. `CONTACT_TRACE_RECORDS` storage config present
10. Contact Lens DLQ is empty

Exit code `0` = all checks passed. Exit code `1` = one or more failed — review output for details.

---

## Step 9 — End-to-End Test Call

### 9.1 Prepare agents

1. Log in as `demo-agent` at `https://smartcx-demo.my.connect.aws/ccp-v2/`
2. Log in as `billing-agent` in a second browser window or incognito tab
3. Set both agents to **Available**

### 9.2 Test scenarios

Call the phone number claimed in Step 5 and exercise each path:

| Press | Expected behavior |
|---|---|
| `1` | Lambda looks up order by ANI. If found, reads order ID, status, and estimated delivery, then disconnects. If not found, plays error message and routes to SupportQueue. |
| `2` | Routes directly to SupportQueue → `demo-agent` receives the call |
| `3` | Routes to BillingQueue → `billing-agent` receives the call |
| `9` | Repeats the main menu |
| _(no input / timeout)_ | Plays fallback message, routes to SupportQueue |

### 9.3 Verify Contact Lens data

After completing test calls, allow 2–5 minutes for Contact Lens post-contact analysis to complete, then:
- Open the dashboard at the CloudFront URL from Step 7
- Verify contacts appear in the contacts table
- Verify sentiment data populates the donut chart
- Verify queue metrics cards show activity

---

## Step 10 — Cost Controls

Set a budget alert to avoid unexpected charges:

1. AWS console → **Billing** → **Budgets** → **Create budget**
2. Type: Cost budget
3. Amount: `$20` (monthly)
4. Alert threshold: 80% actual, notify `alert_email`

Typical demo usage (light testing, no production traffic) stays well under $5/month. The Connect instance itself has no standing charge — costs accrue per contact minute.

---

## Teardown

The teardown script has two modes.

### Demo reset (between sessions — no infrastructure changes)

Clears the contacts and flagged-contacts tables, then re-seeds the orders table. The Connect instance, phone number, and all AWS infrastructure remain running. Use this between demo sessions to restore a clean data state.

```bash
cd infrastructure/scripts
bash teardown.sh --data-only
```

> The Connect instance has no standing charge — there is no cost reason to run a full teardown between demos. Prefer `--data-only`.

### Full teardown (done with the project)

Releases phone numbers, empties S3 buckets, and destroys all infrastructure via `terraform destroy`.

```bash
cd infrastructure/scripts
bash teardown.sh
```

The script:
1. Prompts for confirmation
2. Releases any claimed phone numbers (required before destroy)
3. Empties S3 buckets (required before destroy)
4. Runs `terraform destroy`

> After a full teardown, the next deploy will provision a new Connect instance. You will need to claim a new phone number and associate it with `MainIVRFlow` (Step 5 of the setup guide).

> The Lex v2 bot (`SmartCXOrderBot`) is managed by Terraform and is destroyed automatically with `terraform destroy`.

---

## Troubleshooting

**`InvalidContactFlowException` during apply**

Run with `--debug` on a direct CLI call to expose the `problems` array:
```bash
aws connect create-contact-flow \
  --instance-id <id> --name "Debug" --type CONTACT_FLOW \
  --content file://connect/flows/main-ivr-flow.json \
  --debug 2>&1 | grep problems
```

See `docs/connect-flow-json-reference.md` for a full catalog of known schema issues and fixes.

**`CONTACTFLOW_LOGS` attribute — wrong attribute type**

The correct value is `CONTACTFLOW_LOGS` (no underscore between CONTACT and FLOW). `CONTACT_FLOW_LOGS` is rejected.

**Agent users not receiving calls**

Ensure both agents are set to **Available** in the CCP. Soft phone agents must have the CCP tab open and active. Check that the routing profile assigned to each user matches the queue the call is being routed to.

**Lex bot not appearing in Connect**

The bot association is performed by `deploy.sh` via `aws connect associate-bot` after Terraform apply. If the bot is missing, re-run `deploy.sh` or run the association manually:
```bash
BOT_ID=$(cd infrastructure/terraform && terraform output -raw lex_bot_id)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ALIAS_ID=$(aws lexv2-models list-bot-aliases --bot-id "$BOT_ID" --region us-east-1 \
  --query "botAliasSummaries[?botAliasName=='live'].botAliasId | [0]" --output text)
aws connect associate-bot \
  --instance-id $(cd infrastructure/terraform && terraform output -raw connect_instance_id) \
  --lex-v2-bot "AliasArn=arn:aws:lex:us-east-1:${ACCOUNT_ID}:bot-alias/${BOT_ID}/${ALIAS_ID}" \
  --region us-east-1
```
Note: `associate-lex-bot` is Lex v1 only — `associate-bot` supports both v1 and v2.
