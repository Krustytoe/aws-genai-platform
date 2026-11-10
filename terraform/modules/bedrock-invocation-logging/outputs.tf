output "log_group_name" {
  description = "CloudWatch log group receiving invocation logs."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the invocation log group."
  value       = aws_cloudwatch_log_group.this.arn
}

output "bucket_name" {
  description = "S3 bucket holding full invocation payloads."
  value       = aws_s3_bucket.this.id
}

output "kms_key_arn" {
  description = "KMS key protecting the logs (created or supplied)."
  value       = local.kms_key_arn
}

output "role_arn" {
  description = "IAM role Bedrock assumes to deliver logs."
  value       = aws_iam_role.this.arn
}
