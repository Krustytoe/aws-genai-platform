output "guardrail_id" {
  description = "Guardrail ID, passed to Converse as guardrailIdentifier."
  value       = aws_bedrock_guardrail.this.guardrail_id
}

output "guardrail_arn" {
  description = "Guardrail ARN, used in IAM bedrock:GuardrailIdentifier conditions."
  value       = aws_bedrock_guardrail.this.guardrail_arn
}

output "guardrail_version" {
  description = "Published version to pin in the application, or DRAFT when publish_version is false."
  value       = var.publish_version ? aws_bedrock_guardrail_version.this[0].version : "DRAFT"
}
