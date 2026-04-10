output "cluster_name" {
  description = "Nombre del ECS Cluster"
  value       = aws_ecs_cluster.main.name
}

output "cluster_arn" {
  description = "ARN del ECS Cluster"
  value       = aws_ecs_cluster.main.arn
}

output "service_name" {
  description = "Nombre del ECS Service"
  value       = aws_ecs_service.api.name
}

output "task_definition_arn" {
  description = "ARN de la Task Definition activa"
  value       = aws_ecs_task_definition.api.arn
}

output "ecs_sg_id" {
  description = "ID del Security Group del ECS service"
  value       = aws_security_group.ecs.id
}

output "log_group_name" {
  description = "Nombre del CloudWatch Log Group del ECS service"
  value       = aws_cloudwatch_log_group.ecs.name
}
