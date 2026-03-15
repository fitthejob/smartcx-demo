variable "project_name"            {}
variable "aws_region"              {}
variable "order_lookup_lambda_arn" {}

variable "agent_password" {
  description = "Initial password for demo agent users. Must meet Connect policy: 8+ chars, upper, lower, number, special character."
  sensitive   = true
}
