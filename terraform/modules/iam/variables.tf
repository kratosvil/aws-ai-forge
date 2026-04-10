variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN del bucket S3 de documentos — scope para el policy de lectura"
  type        = string
}

variable "bedrock_model_id" {
  description = "Model ID de Bedrock — scope para el policy de invocación"
  type        = string
}
