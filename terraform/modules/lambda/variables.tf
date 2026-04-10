variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN del IAM Role para la función Lambda"
  type        = string
}

variable "bedrock_model_id" {
  description = "Model ID de Amazon Bedrock a invocar"
  type        = string
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 7
}

variable "lambda_timeout" {
  description = "Timeout de la función Lambda en segundos (Bedrock puede tardar)"
  type        = number
  default     = 30
}

variable "lambda_memory_mb" {
  description = "Memoria asignada a la función Lambda en MB"
  type        = number
  default     = 256
}
