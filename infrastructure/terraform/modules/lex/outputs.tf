output "bot_id" {
  description = "Lex v2 bot ID — used by deploy.sh to resolve the 'live' alias ARN after apply"
  value       = aws_lexv2models_bot.smartcx.id
}
