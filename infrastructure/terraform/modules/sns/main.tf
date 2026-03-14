# Module: sns
# Provisions the smartcx-alerts SNS topic and email subscription.
# All CloudWatch alarms and the contact-lens-handler Lambda publish to this topic.

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
