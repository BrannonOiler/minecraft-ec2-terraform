output "discord_bot_lambda_function_url" {
  description = "Public Discord interactions endpoint URL."
  value       = aws_lambda_function_url.discord_bot_handler_url.function_url
}
