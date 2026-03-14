# Module: lambda
# Provisions all three Lambda functions with IAM roles, CloudWatch log groups,
# X-Ray tracing, DLQ for contact-lens-handler, and packaging via archive_file.
#
# Lambda packaging pattern:
#   deploy.sh pre-installs deps into lambda/<name>/package/ before terraform apply.
#   archive_file zips the entire lambda/<name>/ directory (including package/).
#   Add lambda/**/package/ and lambda/**/*.zip to .gitignore.

data "aws_caller_identity" "current" {}

# ─────────────────────────────────────────────
# Dead Letter Queue — contact-lens-handler only
# ─────────────────────────────────────────────
# Why: EventBridge retries async Lambda invocations twice on failure, then silently
# drops the event. The DLQ captures dropped events so no contact record is permanently lost.
# order-lookup and dashboard-api are synchronous — DLQs do not apply to sync invocations.

resource "aws_sqs_queue" "contact_lens_dlq" {
  name                      = "${var.project_name}-contact-lens-dlq"
  message_retention_seconds = 1209600 # 14 days
}

# ─────────────────────────────────────────────
# Lambda packaging
# ─────────────────────────────────────────────

data "archive_file" "order_lookup" {
  type        = "zip"
  source_dir  = "${var.lambda_root}/order-lookup"
  output_path = "${var.lambda_root}/order-lookup.zip"
}

data "archive_file" "contact_lens_handler" {
  type        = "zip"
  source_dir  = "${var.lambda_root}/contact-lens-handler"
  output_path = "${var.lambda_root}/contact-lens-handler.zip"
}

data "archive_file" "dashboard_api" {
  type        = "zip"
  source_dir  = "${var.lambda_root}/dashboard-api"
  output_path = "${var.lambda_root}/dashboard-api.zip"
}

# ─────────────────────────────────────────────
# order-lookup
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "order_lookup" {
  name              = "/aws/lambda/${var.project_name}-order-lookup"
  retention_in_days = 14
}

resource "aws_iam_role" "order_lookup" {
  name = "${var.project_name}-order-lookup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "order_lookup" {
  name = "inline"
  role = aws_iam_role.order_lookup.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Query"]
        Resource = [
          var.orders_table_arn,
          "${var.orders_table_arn}/index/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.order_lookup.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_function" "order_lookup" {
  function_name    = "${var.project_name}-order-lookup"
  role             = aws_iam_role.order_lookup.arn
  filename         = data.archive_file.order_lookup.output_path
  source_code_hash = data.archive_file.order_lookup.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"

  # Connect's Invoke Lambda block hard-times out at 8s — match it exactly.
  # Do NOT set reserved_concurrent_executions — Connect can spike to multiple
  # simultaneous calls and throttling would cause Connect to follow the error branch.
  timeout = 8

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      ORDERS_TABLE_NAME       = var.orders_table_name
      ORDERS_PHONE_INDEX_NAME = var.orders_phone_index_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.order_lookup]
}

# Allow Amazon Connect to invoke this Lambda
resource "aws_lambda_permission" "order_lookup_connect" {
  statement_id  = "AllowConnectInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_lookup.function_name
  principal     = "connect.amazonaws.com"
  source_arn    = var.connect_instance_arn
}

# ─────────────────────────────────────────────
# contact-lens-handler
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "contact_lens_handler" {
  name              = "/aws/lambda/${var.project_name}-contact-lens-handler"
  retention_in_days = 14
}

resource "aws_iam_role" "contact_lens_handler" {
  name = "${var.project_name}-contact-lens-handler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "contact_lens_handler" {
  name = "inline"
  role = aws_iam_role.contact_lens_handler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.contacts_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.flagged_table_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.contact_lens_dlq.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.contact_lens_handler.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_function" "contact_lens_handler" {
  function_name    = "${var.project_name}-contact-lens-handler"
  role             = aws_iam_role.contact_lens_handler.arn
  filename         = data.archive_file.contact_lens_handler.output_path
  source_code_hash = data.archive_file.contact_lens_handler.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30

  tracing_config {
    mode = "Active"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.contact_lens_dlq.arn
  }

  environment {
    variables = {
      CONTACTS_TABLE_NAME    = var.contacts_table_name
      FLAGGED_TABLE_NAME     = var.flagged_table_name
      SNS_ALERT_TOPIC_ARN    = var.sns_topic_arn
      SENTIMENT_THRESHOLD    = var.sentiment_threshold
      RECORDINGS_BUCKET_NAME = var.recordings_bucket_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.contact_lens_handler]
}

# Disable EventBridge retries — rely on DLQ instead of double-writing contact records
resource "aws_lambda_function_event_invoke_config" "contact_lens_handler" {
  function_name          = aws_lambda_function.contact_lens_handler.function_name
  maximum_retry_attempts = 0
}

# ─────────────────────────────────────────────
# dashboard-api
# ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "dashboard_api" {
  name              = "/aws/lambda/${var.project_name}-dashboard-api"
  retention_in_days = 14
}

resource "aws_iam_role" "dashboard_api" {
  name = "${var.project_name}-dashboard-api-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dashboard_api" {
  name = "inline"
  role = aws_iam_role.dashboard_api.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = [
          var.contacts_table_arn,
          "${var.contacts_table_arn}/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:Query"]
        Resource = [
          var.flagged_table_arn,
          "${var.flagged_table_arn}/index/*",
        ]
      },
      {
        # connect:ListQueues and GetCurrentMetricData require resource ARN with instance ID.
        # The trailing /* is required — Connect does not support resource-level restrictions
        # below the instance for these read-only metric APIs.
        Effect = "Allow"
        Action = [
          "connect:GetCurrentMetricData",
          "connect:ListQueues",
        ]
        Resource = "arn:aws:connect:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${var.connect_instance_id}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "${aws_cloudwatch_log_group.dashboard_api.arn}:*"
      },
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_lambda_function" "dashboard_api" {
  function_name    = "${var.project_name}-dashboard-api"
  role             = aws_iam_role.dashboard_api.arn
  filename         = data.archive_file.dashboard_api.output_path
  source_code_hash = data.archive_file.dashboard_api.output_base64sha256
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      CONTACTS_TABLE_NAME      = var.contacts_table_name
      CONTACTS_DATE_INDEX_NAME = var.contacts_date_index_name
      FLAGGED_TABLE_NAME       = var.flagged_table_name
      FLAGGED_DATE_INDEX_NAME  = var.flagged_date_index_name
      CONNECT_INSTANCE_ID      = var.connect_instance_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.dashboard_api]
}

# Allow API Gateway to invoke this Lambda
resource "aws_lambda_permission" "dashboard_api_apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dashboard_api.function_name
  principal     = "apigateway.amazonaws.com"
}
