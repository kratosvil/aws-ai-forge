locals {
  name_prefix = "${var.project_name}-${var.environment}"
  bucket_name = "${local.name_prefix}-documents-${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

# ── Bucket principal ──────────────────────────────────────────────────────────
resource "aws_s3_bucket" "documents" {
  bucket = local.bucket_name

  # force_destroy = false en producción; true solo para facilitar destroy en labs
  force_destroy = true

  tags = {
    Name = local.bucket_name
  }
}

# ── Bloqueo de acceso público — todos los canales bloqueados ──────────────────
resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── Server-Side Encryption con clave gestionada por AWS (SSE-S3) ──────────────
# Para datos más sensibles usar SSE-KMS con CMK — suficiente SSE-S3 para lab
resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ── Versionado ────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ── Lifecycle — expirar versiones antiguas para controlar costo ───────────────
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  # Depende del versionado para que la regla de noncurrent aplique
  depends_on = [aws_s3_bucket_versioning.documents]

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "STANDARD_IA"
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 3
    }
  }
}

# ── Bucket policy — deniega explícitamente cualquier acceso sin TLS ───────────
resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id

  # Esperar al bloqueo de acceso público antes de aplicar el policy
  depends_on = [aws_s3_bucket_public_access_block.documents]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.documents.arn,
          "${aws_s3_bucket.documents.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
