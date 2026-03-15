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

## Step 2 — Manual Lex v2 Bot Build

> **Why manual:** The Terraform AWS provider (v5.x) does not support Lex v2 bot content creation. The bot must be built once in the console. The Connect association is done via the Connect console after apply (Step 4.2).

### 2.1 Create the bot

1. Open **Amazon Lex** in the AWS console — use the same region as your deployment (`us-east-1`)
2. **Create bot** → name: `SmartCXOrderBot`
   - Runtime role: create new role with basic Lex permissions
   - COPPA: No
   - Idle session timeout: 5 minutes
   - Language settings: English (US), any voice

### 2.2 Configure intents

**Intent 1: `CheckOrderStatus`**
- **Add intent** → **Add empty intent** → name: `CheckOrderStatus`
- Sample utterances:
  ```
  check my order
  order status
  where is my order
  track my order
  track my package
  what is my order status
  I want to check on my order
  ```
- Slots: none — order lookup uses the caller's phone number (ANI)
- Initial response: leave blank
- Fulfillment: turn **Active off** — Connect handles fulfillment
- Save intent

**Intent 2: `CancelOrder`**
- Add intent → name: `CancelOrder`
- Sample utterances:
  ```
  cancel my order
  I want to cancel
  cancel order
  ```
- Fulfillment: Active off
- Save intent

**FallbackIntent:** leave as-is (auto-created, no changes needed)

> Do not enable Lambda for initialization or fulfillment on any intent. Do not enable bot-level logging — observability is provided by Contact Lens and Lambda CloudWatch logs.

### 2.3 Build and publish

1. Click **Build** (top right) — wait ~1 minute
2. **Actions** → **Create version** — description: `v1`
3. Left nav → **Aliases** → **Create alias**
   - Name: `live`
   - Associate with version: `Version 1`
   - Click Create

> Connect requires the alias to point to a published version. `$LATEST` is rejected.

### 2.4 Get the alias ARN

```bash
aws lexv2-models list-bots

aws lexv2-models list-bot-aliases --bot-id YOUR_BOT_ID
```

The `botAliasArn` of the `live` alias is the value you need. Format:
```
arn:aws:lex:us-east-1:ACCOUNT_ID:bot-alias/BOT_ID/ALIAS_ID
```

---

## Step 3 — Configure Terraform Variables

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
lex_bot_alias_arn   = "arn:aws:lex:us-east-1:ACCOUNT_ID:bot-alias/BOT_ID/ALIAS_ID"
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

## Step 4.2 — Associate Lex v2 Bot with Connect

> The Terraform AWS provider (v5.x) does not support Lex v2 bot associations. This is a known provider gap. Association is done once via the Connect console.

1. Open the Connect console → your instance → **Channels** → **Amazon Lex**
2. Under **Amazon Lex V2 bots** → **Add Amazon Lex Bot**
3. Select `SmartCXOrderBot` and the `live` alias
4. Click **Save**

Verify the bot appears in the list before proceeding.

---

## Step 4.3 — Enable Contact Flow Logs

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

The seed script populates `smartcx-demo-orders` with sample records keyed by phone number so the order-lookup Lambda has data to return during test calls.

```bash
cd infrastructure/scripts
python seed_dynamodb.py \
  --table smartcx-demo-orders \
  --region us-east-1
```

The script creates orders associated with specific phone numbers. Use those numbers when making test calls (or call from a number in the seed set).

Alternatively, `deploy.sh` accepts a `--seed` flag that runs this automatically.

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

To destroy all resources:

```bash
cd infrastructure/scripts
bash teardown.sh
```

The teardown script:
1. Prompts for confirmation
2. Lists and disassociates any claimed phone numbers
3. Empties S3 buckets (required before Terraform can delete them)
4. Runs `terraform destroy`

> The Lex v2 bot is **not** deleted by Terraform (it was created manually). Delete it separately in the Lex console if no longer needed.

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

Confirm the alias points to a published version (not `$LATEST`). Re-associate via Connect console → Channels → Amazon Lex if needed.
