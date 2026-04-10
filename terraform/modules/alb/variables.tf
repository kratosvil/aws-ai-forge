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

variable "public_subnet_ids" {
  description = "IDs de las subnets públicas donde se despliega el ALB"
  type        = list(string)
}

variable "container_port" {
  description = "Puerto en el que escucha el contenedor FastAPI"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path del health check del target group"
  type        = string
  default     = "/health"
}
