# SmartCX Demo — Setup Guide

End-to-end instructions for deploying the SmartCX Demo stack from scratch.
Steps 1–5 cover infrastructure deployment. Steps 6–10 cover seeding, dashboard, and validation (completed in Phase 7 once deploy scripts are done).

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
Connect, Lex, Lambda, DynamoDB, API Gateway, EventBridge, SNS, SQS, S3, CloudFront, CloudWatch, IAM (role/policy creation), X-Ray.

For a personal AWS account, `AdministratorAccess` is simplest. For a shared account, scope to the services above.

---

## Step 2 — Manual Lex v2 Bot Build

> **Why manual:** The Terraform AWS provider (v5.x) does not support Lex v2 bot content creation. The bot must be built once in the console. The Connect association is handled post-apply via CLI (Step 3.6).

### 2.1 Create the bot

1. Open **Amazon Lex** in the AWS console — use the same region as your deployment (`us-east-1`)
2. **Create bot** → name: `SmartCXOrderBot`
   - Runtime role: create new role with basic Lex permissions
   - COPPA: No
   - Idle session timeout: 5 minutes
   - Language settings: accept defaults (English US, any voice)

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
- Slots: none — order lookup uses the caller's phone number (ANI), no slot collection needed
- Initial response: leave blank
- Fulfillment: turn **Active off** — Connect handles fulfillment, not Lex
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

> Do not enable Lambda for initialization or fulfillment on any intent. Skip bot-level logging — observability is provided by Contact Lens and Lambda CloudWatch logs.

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

```bash
cd infrastructure/terraform
# terraform.tfvars is already present if you cloned with example values — edit it directly
```

Edit `infrastructure/terraform/terraform.tfvars`:
```hcl
aws_region          = "us-east-1"
project_name        = "smartcx-demo"
alert_email         = "your-email@example.com"   # receives negative-sentiment SNS alerts
sentiment_threshold = "-0.5"
lex_bot_alias_arn   = "arn:aws:lex:us-east-1:ACCOUNT_ID:bot-alias/BOT_ID/ALIAS_ID"
```

> `terraform.tfvars` is excluded by `.gitignore` — never commit it.

---

## Step 4 — Terraform Init and Apply

```bash
cd infrastructure/terraform
terraform init
terraform plan    # review — expect ~30 new resources on first full apply
terraform apply
```

> **Existing state note:** If DynamoDB tables were previously applied in isolation (e.g. during development), Terraform will show them as already existing and only add the remaining resources. This is expected — do not import or recreate them.

After apply, capture the outputs:
```bash
terraform output
```

Key outputs to note:

| Output | Used for |
|---|---|
| `api_endpoint` | Dashboard `VITE_API_BASE_URL` env var |
| `connect_instance_id` | Post-apply CLI commands |
| `dashboard_url` | CloudFront URL for the dashboard |
| `bucket_name` | S3 bucket for dashboard static build upload |
| `distribution_id` | CloudFront invalidation after dashboard deploy |

### 4.1 If apply fails on contact flow resources

Amazon Connect validates contact flow JSON server-side. If `aws_connect_contact_flow` resources fail with a schema error:

1. Comment out the three `aws_connect_contact_flow` resources in `modules/connect/main.tf`
2. Re-run `terraform apply` — the instance, queues, routing profiles, and S3 bucket will be created
3. Build the three flows visually in the Connect console following the spec in section 6.5 of the PRD
4. Export each flow: open the flow → **Save** → **Export flow** → save JSON to `connect/flows/`
5. Uncomment the resources, replace the placeholder JSON with the exports, re-run `terraform apply`

---

## Step 3.5 — Enable Contact Flow Logs

Contact flow logs are not a Terraform-managed attribute. Run after apply:

```bash
aws connect update-instance-attribute \
  --instance-id $(terraform output -raw connect_instance_id) \
  --attribute-type CONTACT_FLOW_LOGS \
  --value true \
  --region us-east-1
```

---

## Step 3.6 — Associate Lex v2 Bot with Connect

The Terraform AWS provider only supports Lex v1 bot associations. The Lex v2 association is done via CLI after apply:

```bash
aws connect associate-lex-bot \
  --instance-id $(terraform output -raw connect_instance_id) \
  --lex-v2-bot aliasArn=$(terraform output -raw lex_bot_alias_arn) \
  --region us-east-1
```

Verify: Connect console → **Channels** → **Amazon Lex** → confirm `SmartCXOrderBot` appears.

---

## Step 5 — Create Demo Agent Users and Claim Phone Number

> Agent users have no Terraform support in Connect. Two agents are required to demonstrate queue isolation between `DemoAgentProfile` (SupportQueue) and `BillingAgentProfile` (BillingQueue).

### 5.1 Create agent users

Connect console → **Users** → **User management** → **Add new user**:

**Agent 1 — Support agent:**
- First name: `Demo`, Last name: `Agent`, Username: `demo-agent`
- Routing profile: `DemoAgentProfile`
- Security profile: `Agent`
- Set a temporary password

**Agent 2 — Billing specialist:**
- First name: `Billing`, Last name: `Agent`, Username: `billing-agent`
- Routing profile: `BillingAgentProfile`
- Security profile: `Agent`
- Set a temporary password

### 5.2 Claim a phone number

Connect console → **Channels** → **Phone numbers** → **Claim a number**:
- Type: DID (local) or Toll-free, Country: US
- Associate with flow: `MainIVRFlow`
- Note the number — all test calls use this number

### 5.3 Before running test calls

1. Log in as `demo-agent`: `https://smartcx-demo.my.connect.aws/ccp-v2/`
2. Log in as `billing-agent` in a second browser or incognito window
3. Set both agents to **Available**

Expected routing behavior:
- Press 1 → order status self-service (Lambda lookup)
- Press 2 → `demo-agent` via SupportQueue
- Press 3 → `billing-agent` via BillingQueue (demonstrates queue isolation)

---

## Steps 6–10

To be completed in Phase 7.

- **Step 6** — Seed DynamoDB with demo orders (`infrastructure/scripts/seed_dynamodb.py`)
- **Step 7** — Build and deploy the React dashboard (`infrastructure/scripts/deploy.sh`)
- **Step 8** — Run post-deploy validation (`infrastructure/scripts/validate_connect.py`)
- **Step 9** — Set AWS Budget alert ($20/month)
- **Step 10** — End-to-end test call walkthrough
