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

variable "lex_bot_alias_arn" {
  description = "ARN of the Lex v2 bot alias to associate with the Connect instance. Must point to a published version — $LATEST is rejected by Connect. Build the bot manually first (see docs/setup-guide.md step 2)."
}
