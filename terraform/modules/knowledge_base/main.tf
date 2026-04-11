locals {
  name_prefix     = "${var.project_name}-${var.environment}"
  collection_name = "${local.name_prefix}-kb-col"  # max 32 chars en AOSS
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ════════════════════════════════════════════════════════════════════════════════
# IAM — KB Service Role
# Bedrock asume este rol para leer S3 y escribir en OpenSearch Serverless
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "bedrock_kb" {
  name        = "${local.name_prefix}-bedrock-kb-role"
  description = "Rol de servicio para Bedrock Knowledge Base: acceso a S3 y AOSS"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        # Condition de seguridad: solo la KB de esta cuenta puede asumir este rol
        StringEquals = {
          "aws:SourceAccount" = data.aws_caller_identity.current.account_id
        }
        ArnLike = {
          "aws:SourceArn" = "arn:aws:bedrock:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:knowledge-base/*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_s3" {
  name = "${local.name_prefix}-kb-s3-read"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "S3ReadDocumentsForIndexing"
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        var.s3_bucket_arn,
        "${var.s3_bucket_arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "bedrock_kb_aoss" {
  name = "${local.name_prefix}-kb-aoss-access"
  role = aws_iam_role.bedrock_kb.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AOSSAPIAccess"
      Effect = "Allow"
      Action = ["aoss:APIAccessAll"]
      Resource = [aws_opensearchserverless_collection.main.arn]
    }]
  })
}

# ════════════════════════════════════════════════════════════════════════════════
# OpenSearch Serverless — Security Policies
#
# AWS AOSS requiere tres políticas antes de crear la colección:
#   1. encryption — cifrado de datos en reposo
#   2. network    — control de acceso a nivel de red
#   3. data       — quién puede operar colecciones e índices (access policy)
# ════════════════════════════════════════════════════════════════════════════════

# 1. Cifrado con llave administrada por AWS (sin costo adicional)
resource "aws_opensearchserverless_security_policy" "encryption" {
  name        = "${local.name_prefix}-enc"
  type        = "encryption"
  description = "Cifrado SSE-AWS para coleccion vector KB"

  policy = jsonencode({
    Rules = [{
      ResourceType = "collection"
      Resource     = ["collection/${local.collection_name}"]
    }]
    AWSOwnedKey = true
  })
}

# 2. Red — acceso publico a nivel de red
#    El control real esta en la access policy (IAM-based).
#    Bedrock KB necesita alcanzar la coleccion desde su red de servicio.
resource "aws_opensearchserverless_security_policy" "network" {
  name        = "${local.name_prefix}-net"
  type        = "network"
  description = "Acceso publico de red — control de acceso via IAM access policy"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
      },
      {
        ResourceType = "dashboard"
        Resource     = ["collection/${local.collection_name}"]
      }
    ]
    AllowFromPublic = true
  }])
}

# 3. Access policy — define quien puede leer/escribir en coleccion e indices
#    Principal: rol del servicio Bedrock KB + root de la cuenta (para administracion)
resource "aws_opensearchserverless_access_policy" "main" {
  name        = "${local.name_prefix}-access"
  type        = "data"
  description = "Acceso de lectura/escritura para Bedrock KB service role"

  policy = jsonencode([{
    Rules = [
      {
        ResourceType = "collection"
        Resource     = ["collection/${local.collection_name}"]
        Permission = [
          "aoss:CreateCollectionItems",
          "aoss:DeleteCollectionItems",
          "aoss:UpdateCollectionItems",
          "aoss:DescribeCollectionItems",
        ]
      },
      {
        ResourceType = "index"
        Resource     = ["index/${local.collection_name}/*"]
        Permission = [
          "aoss:CreateIndex",
          "aoss:DeleteIndex",
          "aoss:UpdateIndex",
          "aoss:DescribeIndex",
          "aoss:ReadDocument",
          "aoss:WriteDocument",
        ]
      }
    ]
    # Principal lista los ARN de roles/usuarios con acceso a datos
    Principal = [
      aws_iam_role.bedrock_kb.arn,
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
    ]
  }])
}

# ════════════════════════════════════════════════════════════════════════════════
# OpenSearch Serverless — Collection (vector store)
#
# Tipo VECTORSEARCH: optimizado para busqueda semantica por similitud.
# Bedrock KB crea automaticamente el indice vector al primer ingestion job.
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_opensearchserverless_collection" "main" {
  name        = local.collection_name
  type        = "VECTORSEARCH"
  description = "Vector store para Bedrock KB — ${var.project_name} RAG"

  # Las security policies deben existir antes de crear la coleccion
  depends_on = [
    aws_opensearchserverless_security_policy.encryption,
    aws_opensearchserverless_security_policy.network,
    aws_opensearchserverless_access_policy.main,
  ]
}

# ════════════════════════════════════════════════════════════════════════════════
# Bedrock Knowledge Base
#
# Bedrock crea el indice vector en AOSS automaticamente al primer ingestion job.
# Embedding model: Titan Text Embeddings v2 (dimension 1024, region-native)
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_bedrockagent_knowledge_base" "main" {
  name        = "${local.name_prefix}-kb"
  description = "RAG Knowledge Base — corpus de documentos indexados desde S3"
  role_arn    = aws_iam_role.bedrock_kb.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${data.aws_region.current.name}::foundation-model/${var.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "OPENSEARCH_SERVERLESS"
    opensearch_serverless_configuration {
      collection_arn    = aws_opensearchserverless_collection.main.arn
      vector_index_name = "bedrock-knowledge-base-default-index"
      field_mapping {
        vector_field   = "bedrock-knowledge-base-default-vector"
        text_field     = "AMAZON_BEDROCK_TEXT_CHUNK"
        metadata_field = "AMAZON_BEDROCK_METADATA"
      }
    }
  }

  # Garantizar que los permisos y la coleccion existan antes de crear la KB
  depends_on = [
    aws_iam_role_policy.bedrock_kb_s3,
    aws_iam_role_policy.bedrock_kb_aoss,
    aws_opensearchserverless_access_policy.main,
    aws_opensearchserverless_collection.main,
  ]
}

# ════════════════════════════════════════════════════════════════════════════════
# Bedrock Data Source — S3
#
# Vincula el bucket S3 a la KB como fuente de documentos.
# Chunking fijo: configurable via variables (default: 512 tokens, 20% overlap).
# ════════════════════════════════════════════════════════════════════════════════
resource "aws_bedrockagent_data_source" "s3" {
  name              = "${local.name_prefix}-s3-datasource"
  knowledge_base_id = aws_bedrockagent_knowledge_base.main.id
  description       = "Documentos en S3 — indexacion automatica via Lambda trigger"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn = var.s3_bucket_arn
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = var.chunk_max_tokens
        overlap_percentage = var.chunk_overlap_percentage
      }
    }
  }
}
