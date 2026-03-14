# SmartCX Demo — Setup Guide

TODO: write full setup guide in Phase 7.

## Steps (outline)

1. Prerequisites (AWS account, Terraform >= 1.6, Python 3.12, Node 20+, AWS CLI configured)
2. Manual Lex v2 bot build — must happen **before** `terraform apply`
3. Terraform init, plan, apply
3.5. Enable contact flow logs via CLI
4. Initial contact flow design → export JSON → run `deploy_flows.py`
5. Create demo agent users in Connect console
6. DynamoDB seeding
7. Dashboard deployment
8. Run `validate_connect.py`
9. Set AWS Budget alert ($20/month)
10. End-to-end test
