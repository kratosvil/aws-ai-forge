variable "aws_region" {
  description = "AWS region donde se despliega la infraestructura"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto — usado como prefijo en todos los recursos"
  type        = string
  default     = "aws-ai-forge"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block para la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDRs para subnets públicas (una por AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDRs para subnets privadas (una por AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "availability_zones" {
  description = "AZs a utilizar"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "bedrock_model_id" {
  description = "Model ID de Amazon Bedrock a invocar"
  type        = string
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 7
}

variable "alarm_email" {
  description = "Email para recibir notificaciones de alarmas CloudWatch via SNS"
  type        = string
  default     = "kratosvill@gmail.com"
}
