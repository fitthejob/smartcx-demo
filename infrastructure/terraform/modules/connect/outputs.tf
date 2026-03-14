output "instance_id" {
  description = "Connect instance ID"
  value       = aws_connect_instance.smartcx.id
}

output "instance_arn" {
  description = "Connect instance ARN"
  value       = aws_connect_instance.smartcx.arn
}

output "support_queue_id" {
  description = "SupportQueue queue ID"
  value       = aws_connect_queue.support.queue_id
}

output "billing_queue_id" {
  description = "BillingQueue queue ID"
  value       = aws_connect_queue.billing.queue_id
}

output "main_ivr_flow_id" {
  description = "MainIVRFlow contact flow ID"
  value       = aws_connect_contact_flow.main_ivr.contact_flow_id
}

output "billing_agent_profile_id" {
  description = "BillingAgentProfile routing profile ID"
  value       = aws_connect_routing_profile.billing_agent.routing_profile_id
}

output "recordings_bucket_name" {
  description = "S3 bucket name for call recordings"
  value       = aws_s3_bucket.recordings.id
}

output "lex_bot_alias_arn" {
  description = "Lex v2 bot alias ARN — passed to deploy.sh for post-apply CLI association"
  value       = var.lex_bot_alias_arn
}
