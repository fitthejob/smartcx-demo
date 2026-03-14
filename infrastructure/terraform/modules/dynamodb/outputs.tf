output "orders_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "orders_table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "orders_phone_index_name" {
  value = "customerPhone-index"
}

output "contacts_table_name" {
  value = aws_dynamodb_table.contacts.name
}

output "contacts_table_arn" {
  value = aws_dynamodb_table.contacts.arn
}

output "contacts_date_index_name" {
  value = "date-index"
}

output "flagged_table_name" {
  value = aws_dynamodb_table.flagged_contacts.name
}

output "flagged_table_arn" {
  value = aws_dynamodb_table.flagged_contacts.arn
}

output "flagged_date_index_name" {
  value = "date-index"
}
