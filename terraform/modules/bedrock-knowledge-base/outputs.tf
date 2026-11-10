output "knowledge_base_id" {
  description = "Knowledge base ID, used by the app's Retrieve calls."
  value       = aws_bedrockagent_knowledge_base.this.id
}

output "knowledge_base_arn" {
  description = "Knowledge base ARN, used to scope bedrock:Retrieve."
  value       = aws_bedrockagent_knowledge_base.this.arn
}

output "data_source_id" {
  description = "Data source ID, passed to StartIngestionJob after uploading documents."
  value       = aws_bedrockagent_data_source.docs.data_source_id
}

output "docs_bucket_name" {
  description = "Upload source documents here."
  value       = aws_s3_bucket.docs.id
}

output "docs_bucket_arn" {
  description = "ARN of the source documents bucket."
  value       = aws_s3_bucket.docs.arn
}

output "vector_index_arn" {
  description = "ARN of the S3 Vectors index."
  value       = aws_s3vectors_index.this.index_arn
}

output "role_arn" {
  description = "Service role the knowledge base assumes."
  value       = aws_iam_role.kb.arn
}

output "kms_key_arn" {
  description = "KMS key protecting documents and vectors (created or supplied)."
  value       = local.kms_key_arn
}
