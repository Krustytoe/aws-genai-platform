variable "name" {
  description = "Prefix for the IAM role and KMS alias."
  type        = string
  default     = "bedrock-invocation-logging"

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,48}$", var.name))
    error_message = "name must be 1-48 IAM-safe characters."
  }
}

variable "log_group_name" {
  description = "CloudWatch log group that receives invocation logs."
  type        = string
  default     = "/aws/bedrock/model-invocations"
}

variable "log_retention_days" {
  description = "CloudWatch retention for invocation logs. Default 365 days lines up with common audit-log retention requirements."
  type        = number
  default     = 365

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (e.g. 30, 90, 365, 731)."
  }
}

variable "bucket_name" {
  description = "S3 bucket for full invocation payloads and large (>100 KB) requests. null derives a name from the account ID and region."
  type        = string
  default     = null
}

variable "s3_retention_days" {
  description = "Days before invocation objects in S3 expire."
  type        = number
  default     = 365

  validation {
    condition     = var.s3_retention_days >= 1
    error_message = "s3_retention_days must be at least 1."
  }
}

variable "deliver_text_data" {
  description = "Log prompt and completion text. Needed for audit and offline evals. Prompts may contain sensitive data, which is why everything here is KMS-encrypted and access-scoped."
  type        = bool
  default     = true
}

variable "deliver_image_data" {
  description = "Log image inputs and outputs."
  type        = bool
  default     = false
}

variable "deliver_embedding_data" {
  description = "Log embedding inputs and vectors. Usually noisy and large, so off by default."
  type        = bool
  default     = false
}

variable "kms_key_arn" {
  description = "Existing KMS key for the log group and bucket. null creates a rotating CMK scoped to CloudWatch Logs and Bedrock."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow Terraform to delete the bucket even if it contains logs. Keep false outside of sandboxes."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
