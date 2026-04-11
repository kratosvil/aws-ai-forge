variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "alb_arn" {
  description = "ARN del ALB al que se adjunta el WAF Web ACL"
  type        = string
}
