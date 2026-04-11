variable "project_name" {
  description = "Nombre del proyecto — prefijo para nombrar recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
}

variable "alarm_email" {
  description = "Email para recibir notificaciones de alarmas CloudWatch"
  type        = string
}

variable "lambda_bedrock_handler_name" {
  description = "Nombre de la Lambda bedrock_handler (v1)"
  type        = string
}

variable "lambda_kb_query_name" {
  description = "Nombre de la Lambda kb_query_handler"
  type        = string
}

variable "lambda_kb_sync_name" {
  description = "Nombre de la Lambda kb_sync_handler"
  type        = string
}

variable "ecs_cluster_name" {
  description = "Nombre del ECS Cluster"
  type        = string
}

variable "ecs_service_name" {
  description = "Nombre del ECS Service"
  type        = string
}

variable "alb_arn" {
  description = "ARN del ALB — se extrae el sufijo para las metricas de CloudWatch"
  type        = string
}

variable "target_group_arn" {
  description = "ARN del Target Group — se extrae el sufijo para las metricas de CloudWatch"
  type        = string
}

variable "log_retention_days" {
  description = "Dias de retencion de logs en CloudWatch"
  type        = number
  default     = 7
}

# Thresholds de alarmas — configurables sin tocar el modulo
variable "lambda_error_threshold" {
  description = "Numero de errores Lambda en 5 min que dispara la alarma"
  type        = number
  default     = 3
}

variable "ecs_cpu_threshold" {
  description = "Porcentaje de CPU de ECS que dispara la alarma"
  type        = number
  default     = 80
}

variable "ecs_memory_threshold" {
  description = "Porcentaje de memoria de ECS que dispara la alarma"
  type        = number
  default     = 80
}

variable "alb_5xx_threshold" {
  description = "Numero de respuestas 5XX del ALB en 5 min que dispara la alarma"
  type        = number
  default     = 10
}
