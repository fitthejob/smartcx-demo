variable "aws_region" {
  description = "AWS region to deploy into"
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name prefix used for all resource names"
  default     = "smartcx-demo"
}

variable "alert_email" {
  description = "Email address for negative-sentiment SNS alert notifications"
}

variable "sentiment_threshold" {
  description = "Customer sentiment score below which a contact is flagged (float as string)"
  default     = "-0.5"
}

variable "agent_password" {
  description = "Initial password for demo-agent and billing-agent Connect users. Must meet Connect policy: 8+ chars, upper, lower, number, special character. Never commit this value — set it in terraform.tfvars."
  sensitive   = true
}

variable "admin_email" {
  description = "Email address for the Cognito dashboard admin user. Never commit this value — set it in terraform.tfvars."
}
