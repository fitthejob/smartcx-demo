variable "project_name"             {}
variable "aws_region"               {}
variable "orders_table_name"        {}
variable "orders_table_arn"         {}
variable "orders_phone_index_name"  {}
variable "contacts_table_name"      {}
variable "contacts_table_arn"       {}
variable "contacts_date_index_name" {}
variable "flagged_table_name"       {}
variable "flagged_table_arn"        {}
variable "flagged_date_index_name"  {}
variable "sns_topic_arn"            {}
variable "sentiment_threshold"      { default = "-0.5" }
variable "connect_instance_id"      {}
variable "connect_instance_arn"     {}
variable "recordings_bucket_name"   {}
