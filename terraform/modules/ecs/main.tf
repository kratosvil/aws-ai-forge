locals {
  name_prefix    = "${var.project_name}-${var.environment}"
  container_name = "${local.name_prefix}-api"
  log_group_name = "/aws/ecs/${local.name_prefix}"
}

data "aws_region" "current" {}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
# Creado explícitamente para controlar retención — ECS no lo gestiona por su cuenta
resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.log_group_name
  }
}

# ── ECS Cluster ───────────────────────────────────────────────────────────────
resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  # Container Insights: métricas de CPU/memoria por tarea en CloudWatch
  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ── Task Definition ───────────────────────────────────────────────────────────
resource "aws_ecs_task_definition" "api" {
  family                   = "${local.name_prefix}-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc" # Requerido para Fargate — cada task tiene su ENI
  cpu                      = var.task_cpu
  memory                   = var.task_memory_mb
  task_role_arn            = var.ecs_task_role_arn
  execution_role_arn       = var.ecs_execution_role_arn

  container_definitions = jsonencode([
    {
      name      = local.container_name
      image     = "${var.ecr_repository_url}:${var.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]

      environment = [
        { name = "LAMBDA_FUNCTION_NAME",    value = var.lambda_function_name },
        { name = "KB_LAMBDA_FUNCTION_NAME", value = var.kb_lambda_function_name },
        { name = "S3_BUCKET_NAME",          value = var.s3_bucket_name },
        { name = "AWS_DEFAULT_REGION",      value = data.aws_region.current.name },
        { name = "PORT",                    value = tostring(var.container_port) }
      ]

      # Configuración de logs — envía stdout/stderr a CloudWatch
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = local.log_group_name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "api"
        }
      }

      # Health check a nivel de contenedor (complementa el del ALB)
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import urllib.request; urllib.request.urlopen('http://localhost:${var.container_port}/health')\" || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60 # Da tiempo al contenedor para arrancar antes del primer check
      }

      # Sin privilegios elevados — el contenedor corre como usuario no-root (definido en Dockerfile)
      privileged             = false
      readonlyRootFilesystem = false
    }
  ])

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# ── Security Group del ECS service ───────────────────────────────────────────
# Solo acepta tráfico desde el SG del ALB — nunca directo desde internet
resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-sg-ecs"
  description = "Permite trafico entrante solo desde el ALB al contenedor FastAPI"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Trafico desde ALB al contenedor"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  egress {
    description = "Salida hacia VPC Endpoints (S3, ECR, Bedrock, CloudWatch) via HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg-ecs"
  }
}

# ── ECS Service ───────────────────────────────────────────────────────────────
resource "aws_ecs_service" "api" {
  name            = "${local.name_prefix}-api-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  # Permite actualizar la imagen sin downtime
  # Al hacer redeploy, ECS levanta la nueva tarea antes de bajar la anterior
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false # Las tareas están en subnets privadas — sin IP pública
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = local.container_name
    container_port   = var.container_port
  }

  # Ignorar cambios en task_definition e image_tag — los deploys los gestiona CI/CD
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_cloudwatch_log_group.ecs]

  tags = {
    Name = "${local.name_prefix}-api-service"
  }
}
