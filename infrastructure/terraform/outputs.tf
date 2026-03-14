output "api_endpoint" {
  description = "API Gateway invoke URL (set as VITE_API_BASE_URL in dashboard/.env)"
  value       = module.api_gateway.api_endpoint
}

output "orders_table_name" {
  value = module.dynamodb.orders_table_name
}

output "contacts_table_name" {
  value = module.dynamodb.contacts_table_name
}

output "flagged_table_name" {
  value = module.dynamodb.flagged_table_name
}

output "alert_topic_arn" {
  value = module.sns.topic_arn
}

output "connect_instance_id" {
  value = module.connect.instance_id
}

output "recordings_bucket_name" {
  value = module.connect.recordings_bucket_name
}

output "bucket_name" {
  description = "S3 bucket hosting the dashboard static build"
  value       = module.cloudfront.bucket_name
}

output "distribution_id" {
  value = module.cloudfront.distribution_id
}

output "dashboard_url" {
  value = "https://${module.cloudfront.distribution_domain_name}"
}

output "contact_lens_dlq_url" {
  value = module.lambda.contact_lens_dlq_url
}

output "contact_lens_dlq_name" {
  value = module.lambda.contact_lens_dlq_name
}
