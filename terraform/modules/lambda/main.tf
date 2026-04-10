locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  function_name     = "${local.name_prefix}-bedrock-handler"
  source_dir        = "${path.root}/../../lambda"
  zip_output_path   = "${path.module}/bedrock_handler.zip"
  log_group_name    = "/aws/lambda/${local.function_name}"
}

# ── Empaquetado del código fuente ─────────────────────────────────────────────
# Terraform empaqueta el directorio lambda/ en un zip antes del deploy
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = local.source_dir
  output_path = local.zip_output_path
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
# Se crea explícitamente para controlar retención — si lo crea Lambda por su cuenta
# queda con retención indefinida (costo no controlado)
resource "aws_cloudwatch_log_group" "lambda" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = {
    Name = local.log_group_name
  }
}

# ── Función Lambda ────────────────────────────────────────────────────────────
resource "aws_lambda_function" "bedrock_handler" {
  function_name    = local.function_name
  description      = "Invoca Amazon Bedrock con pregunta + contexto de documento"
  role             = var.lambda_role_arn
  runtime          = "python3.12"
  handler          = "bedrock_handler.handler"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  timeout     = var.lambda_timeout
  memory_size = var.lambda_memory_mb

  environment {
    variables = {
      BEDROCK_MODEL_ID = var.bedrock_model_id
      MAX_TOKENS       = "1024"
    }
  }

  # Asegurar que el log group exista antes de que Lambda intente escribir en él
  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Name = local.function_name
  }
}

# ── Permiso para que ECS invoque la Lambda ────────────────────────────────────
# resource-based policy — complementa el IAM role del task
resource "aws_lambda_permission" "allow_ecs_invoke" {
  statement_id  = "AllowECSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.bedrock_handler.function_name
  principal     = "ecs-tasks.amazonaws.com"
}
