variable "name" {
  description = "Base name for the knowledge base, vector bucket, index and docs bucket. Lowercase letters, digits and hyphens (S3 Vectors naming rules)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$", var.name))
    error_message = "name must be 3-40 lowercase letters, digits or hyphens, starting and ending with a letter or digit."
  }
}

variable "description" {
  description = "Knowledge base description."
  type        = string
  default     = "Enterprise RAG knowledge base backed by S3 Vectors"
}

variable "embedding_model_id" {
  description = "Bedrock embedding model ID."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "embedding_dimensions" {
  description = "Embedding vector size. Titan Text Embeddings v2 supports 256, 512 or 1024. Must match the index; changing it forces a new index and a full re-ingest."
  type        = number
  default     = 1024

  validation {
    condition     = contains([256, 512, 1024], var.embedding_dimensions)
    error_message = "embedding_dimensions must be 256, 512 or 1024."
  }
}

variable "docs_bucket_name" {
  description = "S3 bucket that holds source documents. null derives a name from the base name, account ID and region."
  type        = string
  default     = null
}

variable "inclusion_prefixes" {
  description = "Only ingest objects under these S3 prefixes. Empty ingests the whole bucket."
  type        = list(string)
  default     = []
}

variable "chunk_max_tokens" {
  description = "Maximum tokens per chunk (fixed-size chunking)."
  type        = number
  default     = 512

  validation {
    condition     = var.chunk_max_tokens >= 20 && var.chunk_max_tokens <= 8192
    error_message = "chunk_max_tokens must be between 20 and 8192."
  }
}

variable "chunk_overlap_percentage" {
  description = "Overlap between adjacent chunks, as a percentage (1-99). Overlap keeps sentences that straddle a boundary retrievable."
  type        = number
  default     = 20

  validation {
    condition     = var.chunk_overlap_percentage >= 1 && var.chunk_overlap_percentage <= 99
    error_message = "chunk_overlap_percentage must be between 1 and 99."
  }
}

variable "kms_key_arn" {
  description = "Existing KMS key for the docs bucket and vector bucket. null creates a rotating CMK."
  type        = string
  default     = null
}

variable "force_destroy" {
  description = "Allow Terraform to delete buckets that still contain data. Keep false outside of sandboxes."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
