# End-to-end wiring: guardrail + knowledge base + invocation logging + private
# endpoints + a least-privilege policy for the app's task role.
#
# Bring your own VPC (e.g. Krustytoe/terraform-aws-platform-modules//modules/vpc-baseline)
# and the IAM role your container runs as.

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.27, < 7.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "Region with Bedrock access to the chosen models (e.g. us-east-1, us-gov-west-1)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VPC the app runs in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the Bedrock interface endpoints."
  type        = list(string)
}

variable "app_security_group_id" {
  description = "Security group of the app (ECS service, EKS pods, Lambda)."
  type        = string
}

variable "app_role_name" {
  description = "IAM role the RAG API runs as."
  type        = string
}

variable "inference_profile_id" {
  description = "Chat model inference profile the app calls."
  type        = string
  default     = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

locals {
  name = "handbook"
  tags = {
    project = "aws-genai-platform"
    managed = "terraform"
  }
}

module "guardrail" {
  source = "../../modules/bedrock-guardrail"

  name = "${local.name}-baseline"
  denied_topics = [{
    name       = "LegalAdvice"
    definition = "Requests for legal advice or interpretation of laws for a specific personal situation."
    examples   = ["Can I sue my landlord?"]
  }]
  tags = local.tags
}

module "knowledge_base" {
  source = "../../modules/bedrock-knowledge-base"

  name = local.name
  tags = local.tags
}

module "invocation_logging" {
  source = "../../modules/bedrock-invocation-logging"

  tags = local.tags
}

module "endpoints" {
  source = "../../modules/bedrock-vpc-endpoints"

  name                       = local.name
  vpc_id                     = var.vpc_id
  subnet_ids                 = var.private_subnet_ids
  allowed_security_group_ids = [var.app_security_group_id]
  tags                       = local.tags
}

module "app_access" {
  source = "../../modules/bedrock-app-access"

  name                  = "${local.name}-rag-api-bedrock"
  inference_profile_ids = [var.inference_profile_id]
  guardrail_arn         = module.guardrail.guardrail_arn
  guardrail_version     = module.guardrail.guardrail_version
  knowledge_base_arns   = [module.knowledge_base.knowledge_base_arn]
  role_name             = var.app_role_name
  tags                  = local.tags
}

# Everything the app needs, in the env var names it reads (see app/README.md).
output "app_environment" {
  description = "Environment variables for the RAG API container."
  value = {
    RAG_PROVIDER          = "bedrock"
    AWS_REGION            = var.region
    RAG_MODEL_ID          = var.inference_profile_id
    RAG_KNOWLEDGE_BASE_ID = module.knowledge_base.knowledge_base_id
    RAG_GUARDRAIL_ID      = module.guardrail.guardrail_id
    RAG_GUARDRAIL_VERSION = module.guardrail.guardrail_version
  }
}

output "ingestion" {
  description = "Upload documents to the bucket, then start an ingestion job (scripts/sync-knowledge-base.sh)."
  value = {
    docs_bucket       = module.knowledge_base.docs_bucket_name
    knowledge_base_id = module.knowledge_base.knowledge_base_id
    data_source_id    = module.knowledge_base.data_source_id
  }
}
