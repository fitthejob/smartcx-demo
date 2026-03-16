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
Connect, Lex, Lambda, DynamoDB, API Gateway, Cognito, EventBridge, SNS, SQS, S3, CloudFront, CloudWatch, IAM (role/policy creation).

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
agent_password      = "YourAgentPassword1!"      # Connect agent login password
admin_email         = "your-email@example.com"   # Cognito dashboard login email
admin_temp_password = "YourTempPassword1!"       # temporary password — you'll change it on first login
```

**Connect password policy** — `agent_password` must meet all of:
- 8 or more characters
- At least one uppercase letter, lowercase letter, number, and special character

**Cognito password policy** — `admin_temp_password` must meet all of:
- 12 or more characters
- At least one uppercase letter, lowercase letter, and number

> `terraform.tfvars` is excluded by `.gitignore` — never commit it. The committed template is `terraform.tfvars.example`.

---

## Step 3 — Deploy

Run the full deploy script from the repo root. It handles everything: Terraform apply, Connect configuration, Cognito user creation, dashboard build, and S3 upload.

```bash
./infrastructure/scripts/deploy.sh --seed
```

`--seed` populates the DynamoDB orders table with demo data on first deploy. Omit it on subsequent deploys if you want to keep existing data.

**What the script does (8 steps):**
1. Packages Lambda dependencies
2. Runs `terraform init` + `terraform apply`
3. Reads Terraform outputs (instance ID, API endpoint, Cognito pool, etc.)
4. Enables contact flow logs and associates the Lex v2 bot with Connect
5. Builds the React dashboard (writes `.env` from Terraform outputs, runs `npm build`)
6. Uploads dashboard to S3 and invalidates CloudFront
7. Seeds DynamoDB orders table (if `--seed`)
8. Runs post-deploy validation

**What Terraform provisions (~45 resources):**
- Cognito user pool, app client, and admin user
- Lex v2 bot (`SmartCXOrderBot`) with `CheckOrderStatus` and `CancelOrder` intents, published version, and `live` alias
- Connect instance, hours of operation, queues (`SupportQueue`, `BillingQueue`), routing profiles, contact flows (`MainIVRFlow`, `ChatFlow`, `AgentWhisper`)
- Agent users: `demo-agent` and `billing-agent`
- Lambda functions (`order-lookup`, `contact-lens-handler`, `dashboard-api`), IAM roles
- DynamoDB tables (`orders`, `contacts`, `flagged-contacts`)
- API Gateway REST API with Cognito authorizer
- EventBridge rule, SNS topic, SQS DLQ
- S3 buckets (recordings + dashboard), CloudFront distribution
- CloudWatch alarms

---

## Step 4 — Claim a Phone Number

Phone number claiming must be done in the Connect console — it cannot be automated.

1. Connect console → **Channels** → **Phone numbers** → **Claim a number**
2. Type: DID (local) or Toll-free, Country: US
3. Associate with flow: `MainIVRFlow`
4. Note the number — all test calls use this number

> After a full teardown and redeploy, you will need to claim a new number. AWS imposes a 30-day hold on released numbers that makes re-claiming unreliable.

---

## Step 5 — First Login to the Dashboard

Open the dashboard URL printed at the end of the deploy script (also available via `terraform output dashboard_url`).

1. Enter `admin_email` and `admin_temp_password` from `terraform.tfvars`
2. Cognito will prompt you to set a permanent password — do this now
3. You are now logged in

The dashboard is protected by Cognito — all API Gateway endpoints require a valid JWT. Unauthenticated requests are rejected before any Lambda runs.

To log in as a Connect agent:
```
https://smartcx-demo.my.connect.aws/ccp-v2/
```
Use `demo-agent` or `billing-agent` with the `agent_password` from `terraform.tfvars`.

---

## Step 6 — Post-Deploy Validation

The deploy script runs validation automatically as step 8. To run it manually:

```bash
INSTANCE_ID=$(cd infrastructure/terraform && terraform output -raw connect_instance_id)
DLQ_URL=$(cd infrastructure/terraform && terraform output -raw contact_lens_dlq_url)

python infrastructure/scripts/validate_connect.py \
  --instance-id $INSTANCE_ID \
  --dlq-url $DLQ_URL \
  --region us-east-1
```

The script checks:
1. Instance is `ACTIVE`
2. Contact flow logs enabled (`CONTACTFLOW_LOGS`)
3. `SupportQueue` and `BillingQueue` exist
4. `DemoAgentProfile` routing profile exists
5. `MainIVRFlow`, `ChatFlow`, `AgentWhisper` flows exist
6. `order-lookup` Lambda is associated
7. Lex v2 bot is associated
8. `CALL_RECORDINGS` storage config present
9. Contact Lens DLQ is empty

Exit code `0` = all checks passed. Exit code `1` = one or more failed.

---

## Step 7 — End-to-End Test Call

### 7.1 Prepare agents

1. Log in as `demo-agent` at `https://smartcx-demo.my.connect.aws/ccp-v2/`
2. Log in as `billing-agent` in a second browser window or incognito tab
3. Set both agents to **Available**

### 7.2 Test scenarios

Call the phone number claimed in Step 4 and exercise each path:

| Press | Expected behavior |
|---|---|
| `1` | Lambda looks up order by ANI. If found, reads order ID, status, and estimated delivery, then disconnects. If not found, plays error message and routes to SupportQueue. |
| `2` | Routes directly to SupportQueue → `demo-agent` receives the call |
| `3` | Routes to BillingQueue → `billing-agent` receives the call |
| `9` | Repeats the main menu |
| _(no input / timeout)_ | Plays fallback message, routes to SupportQueue |

The seed data uses phone numbers in the `+1616555010x` range. Call from one of those numbers to trigger an ANI-based order lookup.

### 7.3 Verify Contact Lens data

After completing test calls, allow 2–5 minutes for Contact Lens post-contact analysis, then open the dashboard and verify:
- Contacts appear in the contacts table
- Sentiment data populates the donut chart
- Queue metrics cards show activity

---

## Step 8 — Cost Controls

Set a budget alert to avoid unexpected charges:

1. AWS console → **Billing** → **Budgets** → **Create budget**
2. Type: Cost budget, Amount: `$20` (monthly)
3. Alert threshold: 80% actual, notify `alert_email`

Idle cost is ~$1–2/month (CloudWatch log storage). All other services are pay-per-use. Full teardown drops cost to $0.

---

## Teardown

### Demo reset (between sessions)

Clears contacts and flagged-contacts tables, re-seeds orders. Infrastructure stays up.

```bash
./infrastructure/scripts/teardown.sh --data-only
```

### Full teardown

Releases phone numbers, empties S3 buckets, and destroys all infrastructure.

```bash
./infrastructure/scripts/teardown.sh
```

After a full teardown, the next deploy provisions a new Connect instance and Cognito pool. You will need to claim a new phone number (Step 4) and set a permanent password on first login (Step 5).

---

## Troubleshooting

**`InvalidContactFlowException` during apply**

Contact flow JSON schema issues. Run with `--debug` to expose the `problems` array:
```bash
aws connect create-contact-flow \
  --instance-id <id> --name "Debug" --type CONTACT_FLOW \
  --content file://connect/flows/main-ivr-flow.json \
  --debug 2>&1 | grep problems
```

See `docs/connect-flow-json-reference.md` for a catalog of known schema issues.

**`CONTACTFLOW_LOGS` attribute error**

The correct value is `CONTACTFLOW_LOGS` — no underscore between CONTACT and FLOW. `CONTACT_FLOW_LOGS` is rejected by the API.

**Agent users not receiving calls**

Ensure both agents are set to **Available** in the CCP. The CCP tab must be open and active. Verify the routing profile assigned to each user matches the queue the call is being routed to.

**Lex bot not associated with Connect**

The association runs in deploy.sh step 4. Re-run the script or run manually:
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

**Dashboard login not working**

- Confirm `admin_email` and `admin_temp_password` are set correctly in `terraform.tfvars`
- Confirm the Cognito user was created: `aws cognito-idp list-users --user-pool-id <pool-id> --region us-east-1`
- If the user status is anything other than `FORCE_CHANGE_PASSWORD` or `CONFIRMED`, delete and re-run `terraform apply`
- The login form uses `USER_PASSWORD_AUTH` — do not use the Cognito Hosted UI URL

**Dashboard shows CORS errors on API calls**

The API Gateway has gateway responses configured to include `Access-Control-Allow-Origin` on 401/403 errors. If you see CORS errors, the most likely cause is an expired or missing JWT — sign out and sign back in.
