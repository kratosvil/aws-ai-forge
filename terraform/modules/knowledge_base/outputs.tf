output "knowledge_base_id" {
  description = "ID de la Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.main.id
}

output "knowledge_base_arn" {
  description = "ARN de la Bedrock Knowledge Base"
  value       = aws_bedrockagent_knowledge_base.main.arn
}

output "data_source_id" {
  description = "ID del data source S3 vinculado a la Knowledge Base"
  value       = aws_bedrockagent_data_source.s3.data_source_id
}

output "collection_arn" {
  description = "ARN de la coleccion OpenSearch Serverless (vector store)"
  value       = aws_opensearchserverless_collection.main.arn
}

output "collection_endpoint" {
  description = "Endpoint HTTPS de la coleccion OpenSearch Serverless"
  value       = aws_opensearchserverless_collection.main.collection_endpoint
}
