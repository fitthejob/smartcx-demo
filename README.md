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
- AWS CLI configured (`aws configure`)

## Quick Start

```bash
# 1. Build the Lex bot manually first — see docs/setup-guide.md step 2
# 2. Copy and fill in terraform variables
cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars

# 3. Deploy the full stack
./infrastructure/scripts/deploy.sh --seed
```

See [docs/setup-guide.md](docs/setup-guide.md) for the complete step-by-step guide.

## Project Structure

```
smartcx-demo/
├── infrastructure/
│   ├── terraform/          # Modular Terraform — one module per AWS service group
│   └── scripts/            # deploy.sh, teardown.sh, seed_dynamodb.py, validate_connect.py
├── lambda/
│   ├── order-lookup/       # Order status lookup (invoked by Connect flow)
│   ├── contact-lens-handler/  # Sentiment flagging (triggered by EventBridge)
│   └── dashboard-api/      # Analytics API (GET /contacts, /metrics, /queues/live)
├── connect/
│   ├── flows/              # Contact flow JSON — source of truth, version-controlled
│   └── lex/                # Lex v2 bot export
├── dashboard/              # React 18 + Vite + Tailwind analytics dashboard
└── docs/                   # Setup guide, demo script, architecture diagram
```

## Teardown

```bash
./infrastructure/scripts/teardown.sh
```

> **Cost:** ~$1–3/month idle (phone number + CloudFront). Set a $20/month AWS Budget alert.
