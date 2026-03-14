output "api_endpoint" {
  description = "Full invoke URL for the demo stage (set as VITE_API_BASE_URL)"
  value       = aws_api_gateway_stage.demo.invoke_url
}

output "api_name" {
  description = "REST API name — used as CloudWatch alarm dimension"
  value       = aws_api_gateway_rest_api.dashboard.name
}
