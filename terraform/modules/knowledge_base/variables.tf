variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN del bucket S3 de documentos — fuente de datos para la Knowledge Base"
  type        = string
}

variable "embedding_model_id" {
  description = "Model ID del modelo de embeddings en Bedrock"
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "chunk_max_tokens" {
  description = "Tamaño máximo de chunk en tokens para la estrategia de chunking fijo"
  type        = number
  default     = 512
}

variable "chunk_overlap_percentage" {
  description = "Porcentaje de solapamiento entre chunks contiguos"
  type        = number
  default     = 20
}
