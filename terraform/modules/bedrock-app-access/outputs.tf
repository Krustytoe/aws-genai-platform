output "policy_arn" {
  description = "ARN of the managed policy."
  value       = aws_iam_policy.this.arn
}

output "policy_json" {
  description = "Rendered policy document, handy for review in plan output."
  value       = data.aws_iam_policy_document.this.json
}

output "model_arns" {
  description = "Every model and inference-profile ARN the policy grants."
  value       = local.model_arns
}
