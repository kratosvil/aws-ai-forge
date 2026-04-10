output "api_endpoint" {
  description = "Endpoint publico del servicio — http://<dns>/ask"
  value       = "http://${module.alb.alb_dns_name}"
}

output "vpc_id" {
  description = "ID de la VPC creada"
  value       = module.vpc.vpc_id
}

output "ecr_repository_url" {
  description = "URL del repositorio ECR"
  value       = module.ecr.repository_url
}

output "s3_bucket_name" {
  description = "Nombre del bucket S3 para documentos"
  value       = module.s3.bucket_name
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda"
  value       = module.lambda.function_name
}

output "ecs_cluster_name" {
  description = "Nombre del ECS Cluster"
  value       = module.ecs.cluster_name
}
