# bedrock-invocation-logging

## Requirements

Terraform >= 1.7, AWS provider >= 6.0. Run `terraform test` for offline validation (no AWS credentials required).

Turns on Bedrock **model invocation logging** for the region: CloudWatch Logs for search and alerting, plus S3 for full payloads. Both are encrypted with one rotating CMK.

## Why

Invocation logs are the audit trail for AI usage: who called which model with what, and what came back. They're also the raw material for offline evals and cost analysis. Bedrock doesn't log anything by default.

## Gotchas this module handles

- **One per region.** Bedrock allows a single logging configuration per account and region. Use this module once per region, typically from a shared platform stack, not from each app.
- **KMS-encrypted log groups need a key policy grant.** CloudWatch Logs can only use a CMK whose policy names the regional `logs.<region>.amazonaws.com` principal. The grant is scoped with `kms:EncryptionContext:aws:logs:arn` to this one log group.
- **Confused-deputy protection.** The delivery role's trust policy and the bucket policy both require `aws:SourceAccount` and `aws:SourceArn`, so only Bedrock acting for this account can write.
- **Prompts are sensitive.** Text logging is on (needed for audit and evals), so access to the bucket and log group should be restricted to whoever is cleared to read prompts. Image and embedding payloads are off by default.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Prefix for the IAM role and KMS alias. | `"bedrock-invocation-logging"` |
| `log_group_name` | CloudWatch log group that receives invocation logs. | `"/aws/bedrock/model-invocations"` |
| `log_retention_days` | CloudWatch retention for invocation logs. Default 365 days lines up with common audit-log retention requirements. | `365` |
| `bucket_name` | S3 bucket for full invocation payloads and large (>100 KB) requests. null derives a name from the account ID and region. | `null` |
| `s3_retention_days` | Days before invocation objects in S3 expire. | `365` |
| `deliver_text_data` | Log prompt and completion text. Needed for audit and offline evals. Prompts may contain sensitive data, which is why everything here is KMS-encrypted and access-scoped. | `true` |
| `deliver_image_data` | Log image inputs and outputs. | `false` |
| `deliver_embedding_data` | Log embedding inputs and vectors. Usually noisy and large, so off by default. | `false` |
| `kms_key_arn` | Existing KMS key for the log group and bucket. null creates a rotating CMK scoped to CloudWatch Logs and Bedrock. | `null` |
| `force_destroy` | Allow Terraform to delete the bucket even if it contains logs. Keep false outside of sandboxes. | `false` |
| `tags` | Tags applied to every resource. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `log_group_name` | CloudWatch log group receiving invocation logs. |
| `log_group_arn` | ARN of the invocation log group. |
| `bucket_name` | S3 bucket holding full invocation payloads. |
| `kms_key_arn` | KMS key protecting the logs (created or supplied). |
| `role_arn` | IAM role Bedrock assumes to deliver logs. |
