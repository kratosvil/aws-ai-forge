locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Repositorio ECR ───────────────────────────────────────────────────────────
resource "aws_ecr_repository" "api" {
  name                 = "${local.name_prefix}-api"
  image_tag_mutability = "IMMUTABLE" # Tags inmutables — evita sobreescribir una imagen en producción

  # Scan automático en cada push — detecta vulnerabilidades conocidas (CVEs)
  image_scanning_configuration {
    scan_on_push = true
  }

  # Encriptación con clave gestionada por AWS
  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name = "${local.name_prefix}-api"
  }
}

# ── Lifecycle policy ──────────────────────────────────────────────────────────
# Controla cuántas imágenes se retienen — evita acumulación y costo de almacenamiento
resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    rules = [
      # Regla 1: imágenes sin tag (capas intermedias de build) — expirar en 1 día
      {
        rulePriority = 1
        description  = "Expirar imagenes sin tag"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiration_days
        }
        action = { type = "expire" }
      },
      # Regla 2: retener solo las últimas N imágenes tagged
      {
        rulePriority = 2
        description  = "Retener solo las ultimas ${var.image_retention_count} imagenes tagged"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "latest"]
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = { type = "expire" }
      }
    ]
  })
}

# ── Repository policy — acceso restringido a la cuenta actual ─────────────────
resource "aws_ecr_repository_policy" "api" {
  repository = aws_ecr_repository.api.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowECSPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
