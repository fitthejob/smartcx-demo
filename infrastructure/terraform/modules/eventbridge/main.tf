# Module: eventbridge
# Provisions the EventBridge rule that triggers contact-lens-handler
# on every Contact Lens Analysis State Change event from Amazon Connect.
# The Lambda handler itself filters for AnalysisStatus == SUCCEEDED.

resource "aws_cloudwatch_event_rule" "contact_lens" {
  name        = "${var.project_name}-contact-lens-analysis"
  description = "Triggers contact-lens-handler on every Contact Lens analysis completion"

  event_pattern = jsonencode({
    source      = ["aws.connect"]
    detail-type = ["Contact Lens Analysis State Change"]
  })
}

resource "aws_cloudwatch_event_target" "contact_lens_lambda" {
  rule = aws_cloudwatch_event_rule.contact_lens.name
  arn  = var.contact_lens_handler_arn
}

resource "aws_lambda_permission" "eventbridge_invoke" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.contact_lens_handler_function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.contact_lens.arn
}
