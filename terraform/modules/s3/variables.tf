variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "versioning_enabled" {
  description = "Habilita versionado en el bucket"
  type        = bool
  default     = true
}

