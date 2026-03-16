# SmartCX Demo

AI-powered contact center proof-of-concept built on Amazon Connect.
Simulates e-commerce customer support for a fictional company "ShopFlow".

## Architecture

**AWS Services:** Amazon Connect · Lex v2 · Lambda · DynamoDB · API Gateway · Cognito · Contact Lens · EventBridge · SNS · S3 · CloudFront

Everything is fully managed by Terraform. No manual console steps required beyond claiming a phone number (a 30-day AWS hold makes automation unreliable).

## Prerequisites

- AWS account with sufficient IAM permissions
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- Python 3.12
- Node.js 20+
- AWS CLI v2 configured (`aws configure`)

## Quick Start

```bash
# 1. Copy and fill in your variables (never commit terraform.tfvars)
cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
# Edit: aws_region, agent_password, admin_email, admin_temp_password, alert_email

# 2. Run the full deploy (Terraform + Connect config + dashboard build + S3 upload)
./infrastructure/scripts/deploy.sh --seed
```

On first login to the dashboard you will be prompted to set a permanent password.

See [docs/setup-guide.md](docs/setup-guide.md) for the complete guide including phone number claiming and end-to-end verification.

## Project Structure

```
smartcx-demo/
├── infrastructure/
│   ├── terraform/
│   │   ├── main.tf                 # Root module — wires all service modules together
│   │   ├── variables.tf            # Input variables (agent_password, admin_email, etc.)
│   │   ├── outputs.tf              # Terraform outputs consumed by deploy.sh
│   │   ├── terraform.tfvars.example
│   │   └── modules/
│   │       ├── connect/            # Connect instance, queues, flows, hours, users
│   │       ├── lex/                # Lex v2 bot, intents, version, live alias (null_resource workaround)
│   │       ├── cognito/            # User pool, app client, admin user
│   │       ├── lambda/             # All three Lambda functions + IAM roles
│   │       ├── api-gateway/        # REST API, Cognito authorizer, CORS, throttling
│   │       ├── dynamodb/           # orders, contacts, flagged-contacts tables
│   │       ├── cloudfront/         # S3 origin + CloudFront distribution for dashboard
│   │       ├── sns/                # Alert topic + email subscription
│   │       ├── eventbridge/        # Contact Lens post-call event rule
│   │       └── monitoring/         # CloudWatch alarms for Lambda errors and DLQ depth
│   └── scripts/
│       ├── deploy.sh               # Full deploy orchestrator (8 steps)
│       ├── teardown.sh             # Full destroy or --data-only reset
│       ├── seed_dynamodb.py        # Seeds orders table with demo data
│       └── validate_connect.py     # Post-deploy health check
├── lambda/
│   ├── order-lookup/               # Order status lookup (invoked by Connect IVR)
│   ├── contact-lens-handler/       # Sentiment flagging (triggered by EventBridge)
│   └── dashboard-api/              # Analytics API — /contacts, /metrics, /queues/live
├── connect/
│   └── flows/                      # Contact flow JSON (templatefile() — no hardcoded ARNs)
├── dashboard/                      # React 18 + Vite + Tailwind + Recharts
│   └── src/
│       ├── auth/                   # Cognito SDK client, useAuth hook
│       ├── components/             # LoginPage, QueueMetrics, SentimentChart, QueueLivePanel, ContactsTable
│       ├── hooks/                  # useContactsData, useQueueLive
│       └── api/                    # dashboardApi.js — axios + JWT interceptor
└── docs/
    ├── setup-guide.md
    ├── demo-script.md
    ├── project-retrospective.md
    └── telecom-to-connect-bridge.md
```

## Authentication

The dashboard is protected by Amazon Cognito. The API Gateway rejects all unauthenticated requests before any Lambda runs — nothing is publicly accessible.

- User pool and app client are fully managed by Terraform
- Admin user is created automatically during `terraform apply` using credentials from `terraform.tfvars`
- The dashboard uses `amazon-cognito-identity-js` (no Amplify) — JWT is attached to every API call via an axios interceptor
- On first login, Cognito requires a permanent password to be set

## Teardown

```bash
# Reset demo data only (clears contacts, re-seeds orders — leaves infrastructure up)
./infrastructure/scripts/teardown.sh --data-only

# Full destroy (removes all AWS resources)
./infrastructure/scripts/teardown.sh
```

## Idle Cost

~$1–2/month (CloudWatch log storage). All other services are pay-per-use and cost $0 at idle. Full teardown drops cost to $0.

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Lex v2 alias via `null_resource` | `aws_lexv2models_bot_alias` does not exist in the Terraform AWS provider v5.x |
| Alias ARN constructed in deploy.sh | `list-bot-aliases` does not return an ARN field — built from region + account + bot ID + alias ID |
| Contact flows use `templatefile()` | Prevents hardcoded ARNs from breaking after teardown/redeploy |
| Cognito authorizer on API Gateway | Rejects unauthenticated requests at the gateway layer before Lambda runs |
| `USER_PASSWORD_AUTH` flow | SPA client cannot use SRP; `setAuthenticationFlowType()` required before `authenticateUser()` |
| `admin_temp_password` via env var in `null_resource` | Shell interpolation mangles special characters — env var avoids all quoting issues |
| `CONTACT_TRACE_RECORDS` not provisioned | Requires Kinesis (not S3); Contact Lens events flow via EventBridge + Lambda instead |
| EventBridge retries disabled on contact-lens-handler | DLQ used instead to prevent duplicate contact records |
| Lambda `requirements.txt` runtime-only | Test deps (pytest, moto) bloat packages past the 70MB Lambda upload limit |
