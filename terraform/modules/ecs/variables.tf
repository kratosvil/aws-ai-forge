variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "vpc_id" {
  description = "ID de la VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs de las subnets privadas donde corre el servicio ECS"
  type        = list(string)
}

variable "ecr_repository_url" {
  description = "URL del repositorio ECR para la imagen de la API"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "ARN del ECS Task Role — permisos de runtime del contenedor"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "ARN del ECS Execution Role — permisos del agente ECS"
  type        = string
}

variable "lambda_function_name" {
  description = "Nombre de la función Lambda de Bedrock — pasado como variable de entorno al contenedor"
  type        = string
}

variable "kb_lambda_function_name" {
  description = "Nombre de la Lambda kb-query-handler — pasado como variable de entorno al contenedor"
  type        = string
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3 de documentos — pasado como variable de entorno al contenedor"
  type        = string
}

variable "target_group_arn" {
  description = "ARN del Target Group del ALB"
  type        = string
}

variable "alb_sg_id" {
  description = "ID del Security Group del ALB — el ECS solo acepta tráfico desde aquí"
  type        = string
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 7
}

variable "container_port" {
  description = "Puerto en el que escucha el contenedor FastAPI"
  type        = number
  default     = 8080
}

variable "task_cpu" {
  description = "CPU units para el task (256 = 0.25 vCPU)"
  type        = number
  default     = 256
}

variable "task_memory_mb" {
  description = "Memoria en MB para el task"
  type        = number
  default     = 512
}

variable "desired_count" {
  description = "Número de tareas deseadas en el servicio"
  type        = number
  default     = 1
}

variable "image_tag" {
  description = "Tag de la imagen Docker a desplegar"
  type        = string
  default     = "latest"
}
