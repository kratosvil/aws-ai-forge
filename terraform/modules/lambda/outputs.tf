output "function_name" {
  description = "Nombre de la función Lambda"
  value       = aws_lambda_function.bedrock_handler.function_name
}

output "function_arn" {
  description = "ARN de la función Lambda"
  value       = aws_lambda_function.bedrock_handler.arn
}

output "log_group_name" {
  description = "Nombre del CloudWatch Log Group de la Lambda"
  value       = aws_cloudwatch_log_group.lambda.name
}
