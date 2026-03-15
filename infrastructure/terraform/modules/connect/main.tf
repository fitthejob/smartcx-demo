# Module: connect
# Provisions the Amazon Connect instance, hours of operation, queues,
# routing profiles, contact flows, Lambda/Lex associations,
# and recordings S3 bucket with lifecycle management.
#
# Manual prerequisites before terraform apply:
#   1. Build Lex v2 bot SmartCXOrderBot in the console and publish an alias.
#      Pass the alias ARN as var.lex_bot_alias_arn.
#   2. After apply, claim a phone number in the Connect console and associate
#      it with MainIVRFlow. Phone number claiming has no Terraform support.
#   3. Create agent users in the Connect console (see setup-guide.md §5).
#   4. Enable contact flow logs via CLI after instance creation:
#      aws connect update-instance-attribute \
#        --instance-id <id> --attribute-type CONTACT_FLOW_LOGS --value true

# ─────────────────────────────────────────────
# Connect instance
# ─────────────────────────────────────────────

resource "aws_connect_instance" "smartcx" {
  instance_alias                   = var.project_name
  identity_management_type         = "CONNECT_MANAGED"
  inbound_calls_enabled            = true
  outbound_calls_enabled           = false
  contact_lens_enabled             = true
  auto_resolve_best_voices_enabled = true
  multi_party_conference_enabled   = false
}

# ─────────────────────────────────────────────
# Recordings S3 bucket
# ─────────────────────────────────────────────

resource "aws_s3_bucket" "recordings" {
  bucket        = "${var.project_name}-recordings-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket                  = aws_s3_bucket.recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    id     = "expire-recordings-90d"
    status = "Enabled"
    filter {}
    expiration {
      days = 90
    }
  }
}

data "aws_caller_identity" "current" {}

# Connect instance storage config — call recordings
resource "aws_connect_instance_storage_config" "recordings" {
  instance_id   = aws_connect_instance.smartcx.id
  resource_type = "CALL_RECORDINGS"

  storage_config {
    s3_config {
      bucket_name   = aws_s3_bucket.recordings.id
      bucket_prefix = "recordings"
    }
    storage_type = "S3"
  }
}

# ─────────────────────────────────────────────
# Hours of operation
# ─────────────────────────────────────────────

resource "aws_connect_hours_of_operation" "business_hours" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "BusinessHours"
  description = "Mon-Fri 8am-8pm ET"
  time_zone   = "America/New_York"

  config {
    day = "MONDAY"
    start_time {
      hours   = 8
      minutes = 0
    }
    end_time {
      hours   = 20
      minutes = 0
    }
  }
  config {
    day = "TUESDAY"
    start_time {
      hours   = 8
      minutes = 0
    }
    end_time {
      hours   = 20
      minutes = 0
    }
  }
  config {
    day = "WEDNESDAY"
    start_time {
      hours   = 8
      minutes = 0
    }
    end_time {
      hours   = 20
      minutes = 0
    }
  }
  config {
    day = "THURSDAY"
    start_time {
      hours   = 8
      minutes = 0
    }
    end_time {
      hours   = 20
      minutes = 0
    }
  }
  config {
    day = "FRIDAY"
    start_time {
      hours   = 8
      minutes = 0
    }
    end_time {
      hours   = 20
      minutes = 0
    }
  }
}

resource "aws_connect_hours_of_operation" "billing_hours" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "BillingHours"
  description = "Mon-Fri 9am-5pm ET"
  time_zone   = "America/New_York"

  config {
    day = "MONDAY"
    start_time {
      hours   = 9
      minutes = 0
    }
    end_time {
      hours   = 17
      minutes = 0
    }
  }
  config {
    day = "TUESDAY"
    start_time {
      hours   = 9
      minutes = 0
    }
    end_time {
      hours   = 17
      minutes = 0
    }
  }
  config {
    day = "WEDNESDAY"
    start_time {
      hours   = 9
      minutes = 0
    }
    end_time {
      hours   = 17
      minutes = 0
    }
  }
  config {
    day = "THURSDAY"
    start_time {
      hours   = 9
      minutes = 0
    }
    end_time {
      hours   = 17
      minutes = 0
    }
  }
  config {
    day = "FRIDAY"
    start_time {
      hours   = 9
      minutes = 0
    }
    end_time {
      hours   = 17
      minutes = 0
    }
  }
}

# ─────────────────────────────────────────────
# Built-in "Default queue" flow — used as queue_flow_module_id
# ─────────────────────────────────────────────

# data "aws_connect_contact_flow" "default_queue" — temporarily commented out.
# This data source requires the Connect instance to be fully initialized before
# it can query built-in flows. Re-enable after first apply once the instance is active.
# data "aws_connect_contact_flow" "default_queue" {
#   instance_id = aws_connect_instance.smartcx.id
#   name        = "Default queue"
#   type        = "QUEUE_TRANSFER"
# }

# ─────────────────────────────────────────────
# Queues
# ─────────────────────────────────────────────

resource "aws_connect_queue" "support" {
  instance_id           = aws_connect_instance.smartcx.id
  name                  = "SupportQueue"
  description           = "General customer support queue"
  hours_of_operation_id = aws_connect_hours_of_operation.business_hours.hours_of_operation_id
  max_contacts          = 10
}

resource "aws_connect_queue" "billing" {
  instance_id           = aws_connect_instance.smartcx.id
  name                  = "BillingQueue"
  description           = "Billing specialist queue"
  hours_of_operation_id = aws_connect_hours_of_operation.billing_hours.hours_of_operation_id
  max_contacts          = 5
}

# ─────────────────────────────────────────────
# Routing profiles
# ─────────────────────────────────────────────

resource "aws_connect_routing_profile" "demo_agent" {
  instance_id               = aws_connect_instance.smartcx.id
  name                      = "DemoAgentProfile"
  description               = "Demo routing profile — handles voice and chat for support and billing queues"
  default_outbound_queue_id = aws_connect_queue.support.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }
  media_concurrencies {
    channel     = "CHAT"
    concurrency = 3
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.support.queue_id
  }
  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 2
    queue_id = aws_connect_queue.billing.queue_id
  }
  queue_configs {
    channel  = "CHAT"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.support.queue_id
  }
  queue_configs {
    channel  = "CHAT"
    delay    = 0
    priority = 2
    queue_id = aws_connect_queue.billing.queue_id
  }
}

resource "aws_connect_routing_profile" "billing_agent" {
  instance_id               = aws_connect_instance.smartcx.id
  name                      = "BillingAgentProfile"
  description               = "Billing-specialist agents — receives BillingQueue contacts only"
  default_outbound_queue_id = aws_connect_queue.billing.queue_id

  media_concurrencies {
    channel     = "VOICE"
    concurrency = 1
  }
  media_concurrencies {
    channel     = "CHAT"
    concurrency = 2
  }

  queue_configs {
    channel  = "VOICE"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.billing.queue_id
  }
  queue_configs {
    channel  = "CHAT"
    delay    = 0
    priority = 1
    queue_id = aws_connect_queue.billing.queue_id
  }
}

# ─────────────────────────────────────────────
# Contact flows
#
# Flow JSON lives in connect/flows/*.json (version-controlled).
# The initial JSON was authored by hand following the flow logic in the PRD.
# After the instance is live, refine flows in the Connect console, then
# re-export and commit the updated JSON to keep IaC as the source of truth.
# ─────────────────────────────────────────────

resource "aws_connect_contact_flow" "main_ivr" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "MainIVRFlow"
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/../../../../connect/flows/main-ivr-flow.json")
}

resource "aws_connect_contact_flow" "chat_flow" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "ChatFlow"
  type        = "CONTACT_FLOW"
  content     = file("${path.module}/../../../../connect/flows/chat-flow.json")
}

resource "aws_connect_contact_flow" "agent_whisper" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "AgentWhisper"
  type        = "AGENT_WHISPER"
  content     = file("${path.module}/../../../../connect/flows/agent-whisper.json")
}

# ─────────────────────────────────────────────
# Agent users
# ─────────────────────────────────────────────

data "aws_connect_security_profile" "agent" {
  instance_id = aws_connect_instance.smartcx.id
  name        = "Agent"
}

resource "aws_connect_user" "demo_agent" {
  instance_id        = aws_connect_instance.smartcx.id
  name               = "demo-agent"
  password           = var.agent_password
  routing_profile_id = aws_connect_routing_profile.demo_agent.routing_profile_id

  security_profile_ids = [
    data.aws_connect_security_profile.agent.security_profile_id
  ]

  identity_info {
    first_name = "Demo"
    last_name  = "Agent"
  }

  phone_config {
    phone_type  = "SOFT_PHONE"
    auto_accept = false
  }
}

resource "aws_connect_user" "billing_agent" {
  instance_id        = aws_connect_instance.smartcx.id
  name               = "billing-agent"
  password           = var.agent_password
  routing_profile_id = aws_connect_routing_profile.billing_agent.routing_profile_id

  security_profile_ids = [
    data.aws_connect_security_profile.agent.security_profile_id
  ]

  identity_info {
    first_name = "Billing"
    last_name  = "Agent"
  }

  phone_config {
    phone_type  = "SOFT_PHONE"
    auto_accept = false
  }
}

# ─────────────────────────────────────────────
# Lambda & Lex associations
# ─────────────────────────────────────────────

resource "aws_connect_lambda_function_association" "order_lookup" {
  instance_id  = aws_connect_instance.smartcx.id
  function_arn = var.order_lookup_lambda_arn
}

# Lex v2 bot association — intentionally not managed by Terraform.
#
# The aws_connect_bot_association resource only supports Lex v1 (name ≤50 chars).
# Lex v2 associations require passing an alias ARN, which the provider does not support.
# This is a known gap in hashicorp/aws as of v5.x.
#
# The association is performed as a post-apply step in infrastructure/scripts/deploy.sh:
#   aws connect associate-lex-bot \
#     --instance-id <instance_id> \
#     --lex-v2-bot aliasArn=<lex_bot_alias_arn> \
#     --region <region>
#
# See docs/setup-guide.md for the full deploy sequence.
