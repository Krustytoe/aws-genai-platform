variable "name" {
  description = "Name prefix for the endpoints and their security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC to create the interface endpoints in."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets for the endpoint ENIs, one per AZ for availability."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet ID."
  }
}

variable "allowed_cidr_blocks" {
  description = "CIDRs allowed to reach the endpoints on 443."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.allowed_cidr_blocks : can(cidrhost(c, 0)) && c != "0.0.0.0/0"])
    error_message = "allowed_cidr_blocks must be valid CIDRs and must not include 0.0.0.0/0."
  }
}

variable "allowed_security_group_ids" {
  description = "Security groups (e.g. the app's ECS service SG) allowed to reach the endpoints on 443."
  type        = list(string)
  default     = []
}

variable "services" {
  description = "Bedrock service endpoints to create. bedrock-runtime serves InvokeModel/Converse; bedrock-agent-runtime serves knowledge base Retrieve."
  type        = list(string)
  default     = ["bedrock-runtime", "bedrock-agent-runtime"]

  validation {
    condition     = alltrue([for s in var.services : contains(["bedrock", "bedrock-runtime", "bedrock-agent", "bedrock-agent-runtime"], s)])
    error_message = "services may only contain bedrock, bedrock-runtime, bedrock-agent and bedrock-agent-runtime."
  }
}

variable "allowed_principal_org_id" {
  description = "If set, the endpoint policy allows principals from this AWS Organization instead of only this account."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
