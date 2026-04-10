output "repository_url" {
  description = "URL del repositorio ECR — usada en el task definition de ECS"
  value       = aws_ecr_repository.api.repository_url
}

output "repository_arn" {
  description = "ARN del repositorio ECR"
  value       = aws_ecr_repository.api.arn
}

output "repository_name" {
  description = "Nombre del repositorio ECR"
  value       = aws_ecr_repository.api.name
}

output "registry_id" {
  description = "ID del registry (account ID) — usado para el comando docker login"
  value       = aws_ecr_repository.api.registry_id
}
