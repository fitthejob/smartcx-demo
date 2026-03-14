# Module: dynamodb
# Provisions three DynamoDB tables for SmartCX Demo:
#   - smartcx-orders          : order records, GSI on customerPhone for ANI lookup
#   - smartcx-contacts        : all completed contacts written by contact-lens-handler
#   - smartcx-flagged-contacts: contacts with negative sentiment, written by contact-lens-handler

resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }

  attribute {
    name = "customerPhone"
    type = "S"
  }

  global_secondary_index {
    name            = "customerPhone-index"
    hash_key        = "customerPhone"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_dynamodb_table" "contacts" {
  name         = "${var.project_name}-contacts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "contactId"
  range_key    = "timestamp"

  attribute {
    name = "contactId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "contactDate"
    type = "S"
  }

  # date-index: query contacts by date, sorted by timestamp descending
  # Used by /contacts (last 50) and /metrics (contacts today)
  global_secondary_index {
    name            = "date-index"
    hash_key        = "contactDate"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project = var.project_name
  }
}

resource "aws_dynamodb_table" "flagged_contacts" {
  name         = "${var.project_name}-flagged-contacts"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "contactId"
  range_key    = "timestamp"

  attribute {
    name = "contactId"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  attribute {
    name = "contactDate"
    type = "S"
  }

  # date-index: query flagged contacts by date
  # Used by /contacts/flagged and flaggedToday metric
  global_secondary_index {
    name            = "date-index"
    hash_key        = "contactDate"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Project = var.project_name
  }
}
