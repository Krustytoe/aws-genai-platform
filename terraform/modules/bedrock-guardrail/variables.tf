variable "name" {
  description = "Guardrail name. Also used as the version description prefix."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-zA-Z_-]{1,50}$", var.name))
    error_message = "name must be 1-50 characters of letters, digits, '-' or '_'."
  }
}

variable "description" {
  description = "Human-readable description shown in the Bedrock console."
  type        = string
  default     = "Enterprise baseline guardrail: content filters, prompt-attack detection, PII handling, grounding checks."
}

variable "blocked_input_messaging" {
  description = "Message returned to the caller when the guardrail blocks the prompt."
  type        = string
  default     = "Sorry, I can't help with that request."
}

variable "blocked_outputs_messaging" {
  description = "Message returned to the caller when the guardrail blocks the model response."
  type        = string
  default     = "Sorry, I can't share that response."
}

variable "content_filter_strength" {
  description = "Strength applied to the SEXUAL, VIOLENCE, HATE, INSULTS and MISCONDUCT filters on both input and output. One of NONE, LOW, MEDIUM, HIGH."
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["NONE", "LOW", "MEDIUM", "HIGH"], var.content_filter_strength)
    error_message = "content_filter_strength must be NONE, LOW, MEDIUM or HIGH."
  }
}

variable "prompt_attack_strength" {
  description = "Strength of the PROMPT_ATTACK (jailbreak / prompt-injection) input filter. Secure default HIGH; NONE disables it."
  type        = string
  default     = "HIGH"

  validation {
    condition     = contains(["NONE", "LOW", "MEDIUM", "HIGH"], var.prompt_attack_strength)
    error_message = "prompt_attack_strength must be NONE, LOW, MEDIUM or HIGH."
  }
}

variable "pii_entities" {
  description = "PII entity types and the action to take (BLOCK or ANONYMIZE). Defaults block credentials and government/financial identifiers and mask contact details."
  type        = map(string)
  default = {
    US_SOCIAL_SECURITY_NUMBER = "BLOCK"
    CREDIT_DEBIT_CARD_NUMBER  = "BLOCK"
    US_BANK_ACCOUNT_NUMBER    = "BLOCK"
    AWS_ACCESS_KEY            = "BLOCK"
    AWS_SECRET_KEY            = "BLOCK"
    PASSWORD                  = "BLOCK"
    EMAIL                     = "ANONYMIZE"
    PHONE                     = "ANONYMIZE"
  }

  validation {
    condition     = alltrue([for action in values(var.pii_entities) : contains(["BLOCK", "ANONYMIZE"], action)])
    error_message = "Every pii_entities action must be BLOCK or ANONYMIZE."
  }
}

variable "denied_topics" {
  description = "Topics the assistant must refuse, e.g. investment or legal advice. Each needs a name (<=100 chars) and a definition (<=200 chars)."
  type = list(object({
    name       = string
    definition = string
    examples   = optional(list(string), [])
  }))
  default = []

  validation {
    condition     = alltrue([for t in var.denied_topics : length(t.name) <= 100 && length(t.definition) <= 200])
    error_message = "denied_topics names must be <=100 characters and definitions <=200 characters."
  }
}

variable "grounding_threshold" {
  description = "Contextual grounding threshold (0-0.99). Responses scoring below it are blocked as likely hallucinations. null disables the check."
  type        = number
  default     = 0.75

  validation {
    condition     = var.grounding_threshold == null ? true : (var.grounding_threshold >= 0 && var.grounding_threshold < 1)
    error_message = "grounding_threshold must be null or between 0 and 0.99."
  }
}

variable "relevance_threshold" {
  description = "Contextual relevance threshold (0-0.99). Responses that don't answer the query are blocked. null disables the check."
  type        = number
  default     = 0.75

  validation {
    condition     = var.relevance_threshold == null ? true : (var.relevance_threshold >= 0 && var.relevance_threshold < 1)
    error_message = "relevance_threshold must be null or between 0 and 0.99."
  }
}

variable "kms_key_arn" {
  description = "Customer managed KMS key used to encrypt the guardrail. null uses an AWS owned key."
  type        = string
  default     = null
}

variable "publish_version" {
  description = "Publish an immutable guardrail version. Applications should pin a version, not DRAFT, so a console edit can't change production behaviour."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
