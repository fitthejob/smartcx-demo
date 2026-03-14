output "order_lookup_arn" {
  value = aws_lambda_function.order_lookup.arn
}

output "order_lookup_function_name" {
  value = aws_lambda_function.order_lookup.function_name
}

output "contact_lens_handler_arn" {
  value = aws_lambda_function.contact_lens_handler.arn
}

output "contact_lens_handler_function_name" {
  value = aws_lambda_function.contact_lens_handler.function_name
}

output "dashboard_api_arn" {
  value = aws_lambda_function.dashboard_api.arn
}

output "dashboard_api_function_name" {
  value = aws_lambda_function.dashboard_api.function_name
}

output "contact_lens_dlq_url" {
  value = aws_sqs_queue.contact_lens_dlq.url
}

output "contact_lens_dlq_name" {
  value = aws_sqs_queue.contact_lens_dlq.name
}
