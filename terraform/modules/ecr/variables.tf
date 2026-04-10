variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "image_retention_count" {
  description = "Cantidad máxima de imágenes tagged a retener en el repositorio"
  type        = number
  default     = 5
}

variable "untagged_expiration_days" {
  description = "Días antes de expirar imágenes sin tag (capas intermedias de build)"
  type        = number
  default     = 1
}
