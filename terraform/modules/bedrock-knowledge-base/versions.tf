terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.27 added storage_configuration.s3_vectors_configuration on knowledge bases.
      version = ">= 6.27, < 7.0"
    }
  }
}
