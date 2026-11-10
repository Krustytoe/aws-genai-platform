variable "name" {
  description = "Name of the IAM managed policy."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,128}$", var.name))
    error_message = "name must be 1-128 IAM-safe characters."
  }
}

variable "foundation_model_ids" {
  description = "Foundation models the app may invoke directly in this region, e.g. \"amazon.nova-pro-v1:0\"."
  type        = list(string)
  default     = []
}

variable "inference_profile_ids" {
  description = "Cross-region inference profiles the app may invoke, e.g. \"us.anthropic.claude-sonnet-4-5-20250929-v1:0\". Grants the profile plus the underlying model in the regions the profile routes to."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.inference_profile_ids : can(regex("^[a-z-]+\\.[a-z0-9-]+\\..+$", id))])
    error_message = "inference_profile_ids must look like <geo>.<provider>.<model>, e.g. us.anthropic.claude-...."
  }
}

variable "guardrail_arn" {
  description = "Guardrail every model invocation must carry. Enforced with an explicit Deny so it holds even if another policy grants broader Bedrock access."
  type        = string
}

variable "guardrail_version" {
  description = "Pin invocations to one guardrail version (e.g. \"3\"). null allows any published version or DRAFT of the guardrail."
  type        = string
  default     = null
}

variable "knowledge_base_arns" {
  description = "Knowledge bases the app may query with bedrock:Retrieve."
  type        = list(string)
  default     = []
}

variable "role_name" {
  description = "Existing IAM role to attach the policy to, e.g. the ECS task role. null only creates the policy."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to the policy."
  type        = map(string)
  default     = {}
}
