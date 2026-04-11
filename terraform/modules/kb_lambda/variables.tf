variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "knowledge_base_id" {
  description = "ID de la Bedrock Knowledge Base"
  type        = string
}

variable "data_source_id" {
  description = "ID del data source S3 en la Bedrock Knowledge Base"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN del bucket S3 de documentos"
  type        = string
}

variable "s3_bucket_name" {
  description = "Nombre del bucket S3 de documentos (para la notificacion S3)"
  type        = string
}

variable "bedrock_model_id" {
  description = "Model ID de Bedrock para generacion en RetrieveAndGenerate"
  type        = string
}

variable "log_retention_days" {
  description = "Dias de retencion de logs en CloudWatch"
  type        = number
  default     = 7
}

variable "num_results" {
  description = "Numero de chunks a recuperar del vector store por consulta"
  type        = number
  default     = 5
}
