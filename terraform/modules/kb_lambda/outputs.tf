output "kb_query_function_name" {
  description = "Nombre de la Lambda que consulta la Knowledge Base"
  value       = aws_lambda_function.kb_query.function_name
}

output "kb_query_function_arn" {
  description = "ARN de la Lambda kb-query-handler"
  value       = aws_lambda_function.kb_query.arn
}

output "kb_sync_function_name" {
  description = "Nombre de la Lambda que dispara ingestion jobs"
  value       = aws_lambda_function.kb_sync.function_name
}
