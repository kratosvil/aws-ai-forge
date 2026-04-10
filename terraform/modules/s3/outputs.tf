output "bucket_name" {
  description = "Nombre del bucket S3 de documentos"
  value       = aws_s3_bucket.documents.bucket
}

output "bucket_arn" {
  description = "ARN del bucket S3 — usado por el módulo IAM para scoping de permisos"
  value       = aws_s3_bucket.documents.arn
}

output "bucket_id" {
  description = "ID del bucket S3"
  value       = aws_s3_bucket.documents.id
}
