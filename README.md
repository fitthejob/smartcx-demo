# SmartCX Demo

AI-powered contact center proof-of-concept built on Amazon Connect.
Simulates e-commerce customer support for a fictional company "ShopFlow".

## Architecture

![Architecture Diagram](docs/architecture-diagram.png)

**AWS Services:** Amazon Connect · Lex v2 · Lambda · DynamoDB · API Gateway · Contact Lens · EventBridge · SNS · S3 · CloudFront · Terraform

## Prerequisites

- AWS account with sufficient IAM permissions
- [Terraform](https://developer.hashicorp.com/terraform/downloads) >= 1.6
- Python 3.12
- Node.js 20+
- AWS CLI v2 configured (`aws configure`)

## Quick Start

> **Before running anything:** Build the Lex v2 bot manually in the AWS console — see [docs/setup-guide.md](docs/setup-guide.md) Step 2. This must happen before `terraform apply`.

```bash
# 1. Fill in Terraform variables (never commit this file)
edit infrastructure/terraform/terraform.tfvars

# 2. Deploy infrastructure
cd infrastructure/terraform
terraform init
terraform apply

# 3. Post-apply: enable flow logs and associate Lex bot
infrastructure/scripts/deploy.sh --post-apply

# 4. Seed demo data, build and upload dashboard
infrastructure/scripts/deploy.sh --seed --dashboard
```

See [docs/setup-guide.md](docs/setup-guide.md) for the complete step-by-step guide including agent user creation, phone number claiming, and end-to-end verification.

## Project Structure

```
smartcx-demo/
├── infrastructure/
│   ├── terraform/              # Modular IaC — one module per AWS service group
│   │   └── modules/            # dynamodb, lambda, connect, api-gateway, cloudfront,
│   │                           # sns, eventbridge, monitoring
│   └── scripts/                # deploy.sh, teardown.sh, seed_dynamodb.py, validate_connect.py
├── lambda/
│   ├── order-lookup/           # Order status lookup (invoked by Connect contact flow)
│   ├── contact-lens-handler/   # Sentiment flagging (triggered by EventBridge)
│   └── dashboard-api/          # Analytics API — /contacts, /metrics, /queues/live
├── connect/
│   ├── flows/                  # Contact flow JSON — version-controlled source of truth
│   └── lex/                    # Lex v2 bot definition export
├── dashboard/                  # React 18 + Vite + Tailwind + Recharts analytics dashboard
│   └── src/
│       ├── components/         # QueueMetrics, SentimentChart, QueueLivePanel, ContactsTable
│       ├── hooks/              # useContactsData, useQueueLive
│       └── api/                # dashboardApi.js (Axios, VITE_API_BASE_URL)
└── docs/                       # setup-guide.md, demo-script.md, architecture diagram
```

## Teardown

```bash
infrastructure/scripts/teardown.sh
```

> **Cost:** ~$1–3/month idle (Connect phone number + CloudFront). Set a $20/month AWS Budget alert to stay safe.

## Key Design Decisions

| Decision | Rationale |
|---|---|
| Lex v2 bot built manually | Terraform AWS provider v5.x has no Lex v2 bot content support |
| Lex↔Connect association via CLI | `aws_connect_bot_association` only supports Lex v1 (name-based) |
| Contact flow logs enabled via CLI | Not a Terraform-managed instance attribute |
| EventBridge retries disabled on contact-lens-handler | DLQ used instead to prevent duplicate contact records |
| All Lambda responses as strings | Amazon Connect requires string values from Lambda invoke blocks |
