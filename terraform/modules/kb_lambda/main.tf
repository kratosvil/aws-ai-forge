locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ════════════════════════════════════════════════════════════════════════════════
# IAM — Role para kb_query_handler
# Permisos: RetrieveAndGenerate en la KB + InvokeModel + CloudWatch Logs
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "kb_query" {
  name        = "${local.name_prefix}-kb-query-role"
  description = "Rol de Lambda kb-query-handler: consulta Bedrock Knowledge Base"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "kb_query_policy" {
  name = "${local.name_prefix}-kb-query-policy"
  role = aws_iam_role.kb_query.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # RetrieveAndGenerate — scope al ARN de la KB especifica
        Sid    = "BedrockKBRetrieveAndGenerate"
        Effect = "Allow"
        Action = [
          "bedrock:RetrieveAndGenerate",
          "bedrock:Retrieve",
        ]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:knowledge-base/${var.knowledge_base_id}"
        ]
      },
      {
        # InvokeModel — requerido por RetrieveAndGenerate para el paso de generacion
        Sid    = "BedrockInvokeModel"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.bedrock_model_id}"
        ]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-kb-query-handler*"
        ]
      },
      {
        Sid      = "XRayTracingWrite"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = ["*"]
      }
    ]
  })
}

# ════════════════════════════════════════════════════════════════════════════════
# IAM — Role para kb_sync_handler
# Permisos: StartIngestionJob en la KB + S3 read + CloudWatch Logs
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "kb_sync" {
  name        = "${local.name_prefix}-kb-sync-role"
  description = "Rol de Lambda kb-sync-handler: dispara ingestion jobs en Bedrock KB"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "kb_sync_policy" {
  name = "${local.name_prefix}-kb-sync-policy"
  role = aws_iam_role.kb_sync.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockKBStartIngestion"
        Effect = "Allow"
        Action = ["bedrock:StartIngestionJob"]
        Resource = [
          "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:knowledge-base/${var.knowledge_base_id}"
        ]
      },
      {
        # S3 read — Bedrock necesita leer el objeto recien subido durante la indexacion
        Sid    = "S3ReadForIngestion"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsWrite"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
        ]
        Resource = [
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.name_prefix}-kb-sync-handler*"
        ]
      },
      {
        Sid      = "XRayTracingWrite"
        Effect   = "Allow"
        Action   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
        Resource = ["*"]
      }
    ]
  })
}

# ════════════════════════════════════════════════════════════════════════════════
# Lambda — kb_query_handler
# Recibe {question} desde ECS, devuelve {answer, citations}
# ════════════════════════════════════════════════════════════════════════════════
data "archive_file" "kb_query" {
  type        = "zip"
  source_file = "${path.root}/../lambda/kb_query_handler.py"
  output_path = "${path.module}/kb_query_handler.zip"
}

resource "aws_cloudwatch_log_group" "kb_query" {
  name              = "/aws/lambda/${local.name_prefix}-kb-query-handler"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "kb_query" {
  function_name    = "${local.name_prefix}-kb-query-handler"
  role             = aws_iam_role.kb_query.arn
  handler          = "kb_query_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.kb_query.output_path
  source_code_hash = data.archive_file.kb_query.output_base64sha256
  timeout          = 60   # RetrieveAndGenerate puede tardar varios segundos
  memory_size      = 256

  # X-Ray — traza cada invocacion y la llamada a Bedrock KB
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      KB_ID            = var.knowledge_base_id
      BEDROCK_MODEL_ID = var.bedrock_model_id
      NUM_RESULTS      = tostring(var.num_results)
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.kb_query,
    aws_iam_role_policy.kb_query_policy,
  ]
}

# Permiso para que ECS (task role) invoque esta Lambda via VPC Endpoint
resource "aws_lambda_permission" "allow_ecs_invoke_kb_query" {
  statement_id  = "AllowECSTaskInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_query.function_name
  principal     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.name_prefix}-ecs-task-role"
}

# ════════════════════════════════════════════════════════════════════════════════
# Lambda — kb_sync_handler
# Disparada por S3 al subir un documento — inicia ingestion job automaticamente
# ════════════════════════════════════════════════════════════════════════════════
data "archive_file" "kb_sync" {
  type        = "zip"
  source_file = "${path.root}/../lambda/kb_sync_handler.py"
  output_path = "${path.module}/kb_sync_handler.zip"
}

resource "aws_cloudwatch_log_group" "kb_sync" {
  name              = "/aws/lambda/${local.name_prefix}-kb-sync-handler"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "kb_sync" {
  function_name    = "${local.name_prefix}-kb-sync-handler"
  role             = aws_iam_role.kb_sync.arn
  handler          = "kb_sync_handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.kb_sync.output_path
  source_code_hash = data.archive_file.kb_sync.output_base64sha256
  timeout          = 60
  memory_size      = 128

  # X-Ray — traza cada invocacion y la llamada a StartIngestionJob
  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      KB_ID          = var.knowledge_base_id
      DATA_SOURCE_ID = var.data_source_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.kb_sync,
    aws_iam_role_policy.kb_sync_policy,
  ]
}

# Permiso para que S3 invoque esta Lambda al detectar ObjectCreated
resource "aws_lambda_permission" "allow_s3_invoke_kb_sync" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kb_sync.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

# Notificacion S3 — dispara kb_sync_handler en cualquier ObjectCreated
# Nota: solo puede haber un aws_s3_bucket_notification por bucket en Terraform
resource "aws_s3_bucket_notification" "kb_sync_trigger" {
  bucket = var.s3_bucket_name

  lambda_function {
    lambda_function_arn = aws_lambda_function.kb_sync.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3_invoke_kb_sync]
}
