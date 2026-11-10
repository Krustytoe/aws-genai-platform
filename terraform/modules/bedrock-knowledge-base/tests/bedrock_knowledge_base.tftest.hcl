# Offline unit tests: `terraform test` against a mocked provider, no AWS credentials required.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws-us-gov"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111111111111"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-gov-west-1"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws-us-gov:kms:us-gov-west-1:111111111111:key/11111111-1111-1111-1111-111111111111"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws-us-gov:iam::111111111111:role/kb-handbook"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws-us-gov:s3:::handbook-docs-111111111111-us-gov-west-1"
    }
  }

  mock_resource "aws_s3vectors_index" {
    defaults = {
      index_arn = "arn:aws-us-gov:s3vectors:us-gov-west-1:111111111111:bucket/handbook-vectors/index/handbook-index"
    }
  }
}

variables {
  name = "handbook"
}

run "uses_s3_vectors_with_matching_dimensions" {
  command = plan

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.storage_configuration[0].type == "S3_VECTORS"
    error_message = "Knowledge base must use S3 Vectors storage."
  }

  assert {
    condition     = aws_s3vectors_index.this.dimension == 1024 && aws_s3vectors_index.this.distance_metric == "cosine"
    error_message = "Index should default to 1024-d cosine."
  }

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].vector_knowledge_base_configuration[0].embedding_model_configuration[0].bedrock_embedding_model_configuration[0].dimensions == aws_s3vectors_index.this.dimension
    error_message = "Embedding dimensions must match the index dimension."
  }

  assert {
    condition     = contains(aws_s3vectors_index.this.metadata_configuration[0].non_filterable_metadata_keys, "AMAZON_BEDROCK_TEXT")
    error_message = "Bedrock chunk text must be non-filterable metadata."
  }
}

run "partition_aware_embedding_arn" {
  command = plan

  assert {
    condition     = aws_bedrockagent_knowledge_base.this.knowledge_base_configuration[0].vector_knowledge_base_configuration[0].embedding_model_arn == "arn:aws-us-gov:bedrock:us-gov-west-1::foundation-model/amazon.titan-embed-text-v2:0"
    error_message = "Embedding model ARN must be built from the current partition and region."
  }
}

run "encrypted_with_cmk" {
  command = plan

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating CMK should be created by default."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.docs.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Docs bucket must use SSE-KMS."
  }

  assert {
    condition     = one(aws_s3vectors_vector_bucket.this.encryption_configuration).sse_type == "aws:kms"
    error_message = "Vector bucket must use SSE-KMS."
  }
}

# Resource ARNs in the role policy are unknown at plan time; apply against the
# mocked provider (still offline) so they resolve.
run "role_is_scoped" {
  command = apply

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.assume.statement[0].condition :
      c.variable == "aws:SourceArn" && contains(c.values, "arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:knowledge-base/*")
    ])
    error_message = "Role trust must be limited to this account's knowledge bases."
  }

  assert {
    condition = alltrue([
      for st in data.aws_iam_policy_document.kb.statement :
      !contains(st.resources, "*")
    ])
    error_message = "Knowledge base role must not grant on wildcard resources."
  }
}

run "chunking_and_prefixes" {
  command = plan

  variables {
    inclusion_prefixes = ["policies/"]
    chunk_max_tokens   = 300
  }

  assert {
    condition     = aws_bedrockagent_data_source.docs.vector_ingestion_configuration[0].chunking_configuration[0].fixed_size_chunking_configuration[0].max_tokens == 300
    error_message = "Chunk size should follow chunk_max_tokens."
  }

  assert {
    condition     = contains(aws_bedrockagent_data_source.docs.data_source_configuration[0].s3_configuration[0].inclusion_prefixes, "policies/")
    error_message = "Inclusion prefixes should be passed through."
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "Handbook"
  }

  expect_failures = [var.name]
}

run "rejects_unsupported_dimensions" {
  command = plan

  variables {
    embedding_dimensions = 768
  }

  expect_failures = [var.embedding_dimensions]
}
