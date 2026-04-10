locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # ARN del modelo Bedrock — usado para scope mínimo en el policy de Lambda
  bedrock_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"

  # Prefijo de log groups del proyecto — scope para permisos CloudWatch
  log_group_prefix = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/${local.name_prefix}*"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ═══════════════════════════════════════════════════════════════════════════════
# ECS EXECUTION ROLE
# Usada por el agente ECS (no por el contenedor) para:
#   - Pull de imagen desde ECR
#   - Escritura de logs en CloudWatch
# ═══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "ecs_execution" {
  name        = "${local.name_prefix}-ecs-execution-role"
  description = "Permite al agente ECS hacer pull de ECR y escribir logs en CloudWatch"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# AWS managed policy — cubre ECR pull + CloudWatch Logs básico para ECS
resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Policy adicional: escritura de logs en log groups específicos del proyecto
resource "aws_iam_role_policy" "ecs_execution_logs" {
  name = "${local.name_prefix}-ecs-execution-logs"
  role = aws_iam_role.ecs_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CreateLogGroupProject"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup"]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${local.name_prefix}*"
        ]
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# ECS TASK ROLE
# Usada por el contenedor FastAPI en tiempo de ejecución para:
#   - Leer documentos de S3
#   - Invocar la función Lambda de Bedrock
#   - Escribir logs en CloudWatch
# ═══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "ecs_task" {
  name        = "${local.name_prefix}-ecs-task-role"
  description = "Permisos de runtime del contenedor FastAPI: S3 read, Lambda invoke, CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${local.name_prefix}-ecs-task-policy"
  role = aws_iam_role.ecs_task.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 — solo lectura sobre el bucket de documentos
      {
        Sid    = "S3ReadDocuments"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      # Lambda — invocar únicamente la función de este proyecto
      {
        Sid    = "LambdaInvokeBedrock"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${local.name_prefix}-bedrock-handler"
        ]
      },
      # CloudWatch Logs — escritura en log groups del proyecto
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/ecs/${local.name_prefix}*:*"
        ]
      }
    ]
  })
}

# ═══════════════════════════════════════════════════════════════════════════════
# LAMBDA ROLE
# Usada por la función Lambda para:
#   - Invocar Bedrock (solo el modelo configurado)
#   - Escribir logs en CloudWatch
# ═══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "lambda" {
  name        = "${local.name_prefix}-lambda-role"
  description = "Permisos de la Lambda: Bedrock invoke + CloudWatch Logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${local.name_prefix}-lambda-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Bedrock — scope al modelo específico configurado
      {
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [local.bedrock_model_arn]
      },
      # CloudWatch Logs — escritura en log groups de Lambda del proyecto
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}*:*"
        ]
      }
    ]
  })
}
