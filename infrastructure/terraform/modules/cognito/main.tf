# Module: cognito
# Provisions a Cognito User Pool and app client for dashboard authentication.
#
# Design decisions:
#   - Email as username, no self-signup (admin-created users only)
#   - Public SPA client (no client secret — browsers cannot keep secrets)
#   - USER_PASSWORD_AUTH flow: the dashboard calls the Cognito ISP API directly,
#     no hosted UI or Cognito domain needed
#   - No MFA, no advanced security — solo demo owner, cost not justified
#   - 1-hour ID token, 30-day refresh token (survive normal working sessions)

data "aws_region" "current" {}

resource "aws_cognito_user_pool" "this" {
  name = "${var.project_name}-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Advanced security costs money — not needed for a single-owner demo
  user_pool_add_ons {
    advanced_security_mode = "OFF"
  }
}

# ─────────────────────────────────────────────
# Admin user
# ─────────────────────────────────────────────
#
# aws_cognito_user does not exist in the Terraform AWS provider.
# Workaround: null_resource + local-exec using the AWS CLI.
# --message-action SUPPRESS skips the welcome email (no SES setup needed).
# The command is idempotent — re-running deploy on an existing user prints a
# UsernameExistsException which is silently ignored.

resource "null_resource" "admin_user" {
  triggers = {
    user_pool_id = aws_cognito_user_pool.this.id
    admin_email  = var.admin_email
  }

  provisioner "local-exec" {
    # Pass the password as an env var so special characters are never shell-interpolated.
    environment = {
      ADMIN_TEMP_PASSWORD = var.admin_temp_password
    }
    command = <<-EOT
      aws cognito-idp admin-create-user \
        --user-pool-id "${aws_cognito_user_pool.this.id}" \
        --username "${var.admin_email}" \
        --user-attributes Name=email,Value="${var.admin_email}" Name=email_verified,Value=true \
        --temporary-password "$ADMIN_TEMP_PASSWORD" \
        --message-action SUPPRESS \
        --region "${data.aws_region.current.name}" 2>&1 | grep -v UsernameExistsException || true
      echo "    Cognito admin user: ${var.admin_email}"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "aws_cognito_user_pool_client" "dashboard" {
  name         = "${var.project_name}-dashboard-client"
  user_pool_id = aws_cognito_user_pool.this.id

  # No secret — public browser client (SPAs cannot protect a client secret)
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  access_token_validity  = 1  # hours
  id_token_validity      = 1  # hours
  refresh_token_validity = 30 # days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  supported_identity_providers = ["COGNITO"]
}
