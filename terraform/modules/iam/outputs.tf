output "ecs_execution_role_arn" {
  description = "ARN del ECS Execution Role — usado por el agente ECS"
  value       = aws_iam_role.ecs_execution.arn
}

output "ecs_task_role_arn" {
  description = "ARN del ECS Task Role — usado por el contenedor en runtime"
  value       = aws_iam_role.ecs_task.arn
}

output "lambda_role_arn" {
  description = "ARN del Lambda Role — usado por la función Lambda"
  value       = aws_iam_role.lambda.arn
}
