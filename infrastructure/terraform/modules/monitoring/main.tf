# Module: monitoring
# Six CloudWatch metric alarms covering the critical paths of SmartCX Demo.
# All alarms notify the smartcx-alerts SNS topic.
# Alarm rationale is documented inline.

# ─────────────────────────────────────────────
# Lambda alarms
# ─────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "order_lookup_errors" {
  alarm_name          = "${var.project_name}-order-lookup-errors"
  alarm_description   = "order-lookup Lambda errors — callers are hitting the fallback branch instead of hearing their order status"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.order_lookup_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "contact_lens_handler_errors" {
  alarm_name          = "${var.project_name}-contact-lens-handler-errors"
  alarm_description   = "contact-lens-handler Lambda errors — contacts will not appear in the dashboard (silent data loss)"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.contact_lens_handler_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "dashboard_api_errors" {
  alarm_name          = "${var.project_name}-dashboard-api-errors"
  alarm_description   = "dashboard-api Lambda errors — dashboard data is stale or unavailable"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = var.dashboard_api_function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  # Threshold of 3 avoids noise from transient API Gateway cold starts
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "order_lookup_throttles" {
  alarm_name          = "${var.project_name}-order-lookup-throttles"
  alarm_description   = "order-lookup Lambda throttles — Connect follows the error branch, callers get incorrect fallback"
  namespace           = "AWS/Lambda"
  metric_name         = "Throttles"
  dimensions          = { FunctionName = var.order_lookup_function_name }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}

# ─────────────────────────────────────────────
# DLQ alarm
# ─────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "contact_lens_dlq_depth" {
  alarm_name          = "${var.project_name}-contact-lens-dlq-depth"
  alarm_description   = "Contact Lens DLQ has messages — contact events were permanently dropped after all retries"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.contact_lens_dlq_name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
}

# ─────────────────────────────────────────────
# API Gateway alarm
# ─────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "api_gateway_5xx" {
  alarm_name          = "${var.project_name}-api-gateway-5xx"
  alarm_description   = "API Gateway returning 5xx errors — dashboard API is failing"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5XXError"
  dimensions = {
    ApiName  = var.api_gateway_name
    Stage    = "demo"
  }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.sns_topic_arn]
  ok_actions          = [var.sns_topic_arn]
}
