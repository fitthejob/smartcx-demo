terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # TODO: production hardening — replace local backend with S3 + DynamoDB state locking:
  # backend "s3" {
  #   bucket         = "your-tfstate-bucket"
  #   key            = "smartcx-demo/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "your-tfstate-lock-table"
  #   encrypt        = true
  # }
  backend "local" {}
}

provider "aws" {
  region = var.aws_region
}

module "dynamodb" {
  source       = "./modules/dynamodb"
  project_name = var.project_name
}

module "sns" {
  source       = "./modules/sns"
  project_name = var.project_name
  alert_email  = var.alert_email
}

module "lambda" {
  source = "./modules/lambda"

  project_name             = var.project_name
  aws_region               = var.aws_region
  orders_table_name        = module.dynamodb.orders_table_name
  orders_table_arn         = module.dynamodb.orders_table_arn
  orders_phone_index_name  = module.dynamodb.orders_phone_index_name
  contacts_table_name      = module.dynamodb.contacts_table_name
  contacts_table_arn       = module.dynamodb.contacts_table_arn
  contacts_date_index_name = module.dynamodb.contacts_date_index_name
  flagged_table_name       = module.dynamodb.flagged_table_name
  flagged_table_arn        = module.dynamodb.flagged_table_arn
  flagged_date_index_name  = module.dynamodb.flagged_date_index_name
  sns_topic_arn            = module.sns.topic_arn
  sentiment_threshold      = var.sentiment_threshold
  connect_instance_id      = module.connect.instance_id
  connect_instance_arn     = module.connect.instance_arn
  recordings_bucket_name   = module.connect.recordings_bucket_name
}

module "api_gateway" {
  source            = "./modules/api-gateway"
  project_name      = var.project_name
  aws_region        = var.aws_region
  dashboard_api_arn = module.lambda.dashboard_api_arn
}

module "eventbridge" {
  source                             = "./modules/eventbridge"
  project_name                       = var.project_name
  contact_lens_handler_arn           = module.lambda.contact_lens_handler_arn
  contact_lens_handler_function_name = module.lambda.contact_lens_handler_function_name
}

module "cloudfront" {
  source       = "./modules/cloudfront"
  project_name = var.project_name
}

module "connect" {
  source                  = "./modules/connect"
  project_name            = var.project_name
  aws_region              = var.aws_region
  order_lookup_lambda_arn = module.lambda.order_lookup_arn
  lex_bot_alias_arn       = var.lex_bot_alias_arn
}

module "monitoring" {
  source                              = "./modules/monitoring"
  project_name                        = var.project_name
  sns_topic_arn                       = module.sns.topic_arn
  order_lookup_function_name          = module.lambda.order_lookup_function_name
  contact_lens_handler_function_name  = module.lambda.contact_lens_handler_function_name
  dashboard_api_function_name         = module.lambda.dashboard_api_function_name
  contact_lens_dlq_name               = module.lambda.contact_lens_dlq_name
  api_gateway_name                    = module.api_gateway.api_name
}
