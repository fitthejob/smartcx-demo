# Module: lex
# Provisions the SmartCXOrderBot Lex v2 bot, publishes version 1,
# and creates the "live" alias that Connect requires.
#
# Bot design:
#   - Two intents: CheckOrderStatus, CancelOrder
#   - No slots — order lookup is ANI-based (caller phone number), not slot-based
#   - Fulfillment disabled on all intents — Connect handles fulfillment
#   - No Lambda initialization or fulfillment hooks
#   - No bot-level logging — observability via Contact Lens + Lambda CloudWatch
#
# Provider gap workaround:
#   aws_lexv2models_bot_alias does not exist in the Terraform AWS provider
#   (open issue hashicorp/terraform-provider-aws#35780, not planned as of 2026).
#   The alias is created and updated via null_resource + AWS CLI local-exec.
#   The alias ARN is read back via data "external" so it can be used as an output.
#
# Known provider behavior:
#   aws_lexv2models_bot_version creates a new version on every apply even when
#   the bot definition has not changed. The alias update re-points to the new
#   version on each apply, which is safe but noisy in plan output.
#
# Connect requires the alias to point to a published version — $LATEST is rejected.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────
# IAM role for Lex runtime
# ─────────────────────────────────────────────

resource "aws_iam_role" "lex_runtime" {
  name = "${var.project_name}-lex-runtime-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lexv2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lex_runtime" {
  name = "inline"
  role = aws_iam_role.lex_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Lex needs CloudWatch access if conversation logging is enabled.
        # Kept minimal — no Lambda fulfillment, no S3 audio logs for this demo.
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lex/*"
      },
    ]
  })
}

# ─────────────────────────────────────────────
# Bot
# ─────────────────────────────────────────────

resource "aws_lexv2models_bot" "smartcx" {
  name                        = "SmartCXOrderBot"
  role_arn                    = aws_iam_role.lex_runtime.arn
  idle_session_ttl_in_seconds = 300 # 5 minutes

  data_privacy {
    child_directed = false # COPPA: No
  }
}

# ─────────────────────────────────────────────
# Bot locale — English (US)
# ─────────────────────────────────────────────

resource "aws_lexv2models_bot_locale" "en_us" {
  bot_id      = aws_lexv2models_bot.smartcx.id
  bot_version = "DRAFT"
  locale_id   = "en_US"

  # 0.40 is the AWS default — low enough to match short phrases like "order status".
  n_lu_intent_confidence_threshold = 0.40
}

# ─────────────────────────────────────────────
# Intent: CheckOrderStatus
# ─────────────────────────────────────────────

resource "aws_lexv2models_intent" "check_order_status" {
  bot_id      = aws_lexv2models_bot.smartcx.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "CheckOrderStatus"

  sample_utterance { utterance = "check my order" }
  sample_utterance { utterance = "order status" }
  sample_utterance { utterance = "where is my order" }
  sample_utterance { utterance = "track my order" }
  sample_utterance { utterance = "track my package" }
  sample_utterance { utterance = "what is my order status" }
  sample_utterance { utterance = "I want to check on my order" }

  # Fulfillment disabled — Connect handles fulfillment after intent classification.
  fulfillment_code_hook {
    enabled = false
  }
}

# ─────────────────────────────────────────────
# Intent: CancelOrder
# ─────────────────────────────────────────────

resource "aws_lexv2models_intent" "cancel_order" {
  bot_id      = aws_lexv2models_bot.smartcx.id
  bot_version = "DRAFT"
  locale_id   = aws_lexv2models_bot_locale.en_us.locale_id
  name        = "CancelOrder"

  sample_utterance { utterance = "cancel my order" }
  sample_utterance { utterance = "I want to cancel" }
  sample_utterance { utterance = "cancel order" }

  fulfillment_code_hook {
    enabled = false
  }
}

# ─────────────────────────────────────────────
# Bot version
# ─────────────────────────────────────────────
#
# depends_on ensures all intents are fully saved before the version is published.

resource "aws_lexv2models_bot_version" "v1" {
  bot_id = aws_lexv2models_bot.smartcx.id

  locale_specification = {
    en_US = {
      source_bot_version = "DRAFT"
    }
  }

  # ignore_changes = all prevents the provider from publishing a new version on
  # every apply. Without this, aws_lexv2models_bot_version diffs on every run
  # even when the bot definition is unchanged, causing null_resource triggers
  # to fire and an unnecessary update-bot-alias call on each apply.
  # The version is only republished if you taint this resource explicitly:
  #   terraform taint module.lex.aws_lexv2models_bot_version.v1
  lifecycle {
    ignore_changes = all
  }

  depends_on = [
    aws_lexv2models_bot_locale.en_us,
    aws_lexv2models_intent.check_order_status,
    aws_lexv2models_intent.cancel_order,
  ]
}

# ─────────────────────────────────────────────
# Bot alias — "live" (via AWS CLI)
# ─────────────────────────────────────────────
#
# aws_lexv2models_bot_alias is not supported by the Terraform AWS provider
# (hashicorp/terraform-provider-aws#35780). Workaround: null_resource + local-exec.
#
# The script uses `create-bot-alias` on first deploy and `update-bot-alias` on
# subsequent applies (when the version number changes). It checks for existence
# first to decide which command to run.

resource "null_resource" "bot_alias_live" {
  triggers = {
    bot_id      = aws_lexv2models_bot.smartcx.id
    bot_version = aws_lexv2models_bot_version.v1.bot_version
    region      = data.aws_region.current.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      BOT_ID="${aws_lexv2models_bot.smartcx.id}"
      BOT_VERSION="${aws_lexv2models_bot_version.v1.bot_version}"
      REGION="${data.aws_region.current.name}"
      LOCALE_SETTINGS='{"en_US":{"enabled":true}}'

      # Check if alias already exists
      EXISTING=$(aws lexv2-models list-bot-aliases \
        --bot-id "$BOT_ID" \
        --region "$REGION" \
        --query "botAliasSummaries[?botAliasName=='live'].botAliasId | [0]" \
        --output text 2>/dev/null)

      if [ -z "$EXISTING" ] || [ "$EXISTING" = "None" ]; then
        echo "Creating 'live' alias for bot $BOT_ID at version $BOT_VERSION"
        aws lexv2-models create-bot-alias \
          --bot-id "$BOT_ID" \
          --bot-alias-name "live" \
          --bot-version "$BOT_VERSION" \
          --bot-alias-locale-settings "$LOCALE_SETTINGS" \
          --region "$REGION"
      else
        echo "Updating 'live' alias $EXISTING for bot $BOT_ID to version $BOT_VERSION"
        aws lexv2-models update-bot-alias \
          --bot-id "$BOT_ID" \
          --bot-alias-id "$EXISTING" \
          --bot-alias-name "live" \
          --bot-version "$BOT_VERSION" \
          --bot-alias-locale-settings "$LOCALE_SETTINGS" \
          --region "$REGION"
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

  # Delete the alias before terraform destroys the bot version.
  # Without this, DeleteBotVersion fails with ConflictException (409) because
  # the version is still referenced by the alias.
  # self.triggers preserves bot_id and region from creation time so they are
  # available here even after the bot resource itself is queued for deletion.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      BOT_ID="${self.triggers.bot_id}"
      REGION="${self.triggers.region}"

      ALIAS_ID=$(aws lexv2-models list-bot-aliases \
        --bot-id "$BOT_ID" \
        --region "$REGION" \
        --query "botAliasSummaries[?botAliasName=='live'].botAliasId | [0]" \
        --output text 2>/dev/null)

      if [ -z "$ALIAS_ID" ] || [ "$ALIAS_ID" = "None" ]; then
        echo "No 'live' alias found — skipping delete"
      else
        echo "Deleting 'live' alias $ALIAS_ID from bot $BOT_ID"
        aws lexv2-models delete-bot-alias \
          --bot-id "$BOT_ID" \
          --bot-alias-id "$ALIAS_ID" \
          --region "$REGION"
      fi
    EOT
    interpreter = ["bash", "-c"]
  }

}

# ─────────────────────────────────────────────
# Destroy ordering: alias before version
# ─────────────────────────────────────────────
#
# Terraform cannot express "destroy A before B" without a dependency edge.
# Adding bot_version → null_resource creates a cycle (null_resource triggers
# already reference bot_version). Instead, a separate null_resource with no
# create-time side effects carries the depends_on in one direction only.
# On destroy, Terraform reverses depends_on: bot_version_destroy_fence is
# destroyed before bot_version, and bot_alias_live is destroyed before
# bot_version_destroy_fence — giving the required order:
#   alias deleted → version deleted → bot deleted.

resource "null_resource" "bot_version_destroy_fence" {
  depends_on = [
    null_resource.bot_alias_live,
    aws_lexv2models_bot_version.v1,
  ]
}

# Note: the alias ARN is not exposed as a Terraform output.
# data "external" is racy on first apply — the null_resource creates the alias
# during apply execution, but data sources evaluate before outputs are written,
# so the ARN lookup returns "None" on fresh deploys.
#
# Instead, deploy.sh resolves the alias ARN directly via AWS CLI after apply:
#   aws lexv2-models list-bot-aliases --bot-id <id> \
#     --query "botAliasSummaries[?botAliasName=='live'].botAliasArn | [0]"
# The bot ID is available as a Terraform output (lex_bot_id).
