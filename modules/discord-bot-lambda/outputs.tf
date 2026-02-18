output "discord_bot_lambda_function_url" {
  value = aws_lambda_function_url.discord_bot_handler_url.function_url
}
