output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN — passed to API Gateway authorizer"
  value       = aws_cognito_user_pool.this.arn
}

output "client_id" {
  description = "Cognito App Client ID (public — safe to expose in dashboard bundle)"
  value       = aws_cognito_user_pool_client.dashboard.id
}

output "region" {
  description = "AWS region of the user pool — needed by the browser SDK"
  value       = data.aws_region.current.name
}
