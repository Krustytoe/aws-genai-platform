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
      arn = "arn:aws-us-gov:iam::111111111111:role/bedrock-invocation-logging"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws-us-gov:s3:::bedrock-invocation-logs-111111111111-us-gov-west-1"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws-us-gov:logs:us-gov-west-1:111111111111:log-group:/aws/bedrock/model-invocations"
    }
  }
}

run "creates_cmk_and_encrypts_everything" {
  command = plan

  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation
    error_message = "A rotating CMK should be created when kms_key_arn is null."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Bucket must use SSE-KMS."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this.retention_in_days == 365
    error_message = "Log retention should default to 365 days."
  }
}

run "partition_aware_bucket_name" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "bedrock-invocation-logs-111111111111-us-gov-west-1"
    error_message = "Derived bucket name should include account and region."
  }
}

run "text_on_images_and_embeddings_off" {
  command = plan

  assert {
    condition = (
      aws_bedrock_model_invocation_logging_configuration.this.logging_config[0].text_data_delivery_enabled &&
      !aws_bedrock_model_invocation_logging_configuration.this.logging_config[0].image_data_delivery_enabled &&
      !aws_bedrock_model_invocation_logging_configuration.this.logging_config[0].embedding_data_delivery_enabled
    )
    error_message = "Defaults should log text only."
  }
}

run "uses_supplied_key" {
  command = plan

  variables {
    kms_key_arn = "arn:aws-us-gov:kms:us-gov-west-1:111111111111:key/00000000-0000-0000-0000-000000000000"
  }

  assert {
    condition     = length(aws_kms_key.this) == 0 && aws_cloudwatch_log_group.this.kms_key_id == var.kms_key_arn
    error_message = "Supplied key should be used and no key created."
  }
}

# The policy documents are rendered by a mocked data source, so assert on the
# statements the module feeds into them rather than on the rendered JSON.
run "trust_and_bucket_policies_are_scoped" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.assume.statement[0].condition :
      c.variable == "aws:SourceAccount" && contains(c.values, "111111111111")
      ]) && anytrue([
      for c in data.aws_iam_policy_document.assume.statement[0].condition :
      c.variable == "aws:SourceArn" && contains(c.values, "arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:*")
    ])
    error_message = "Role trust must pin aws:SourceAccount and aws:SourceArn (confused-deputy protection)."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.bucket.statement :
      st.sid == "DenyInsecureTransport" && st.effect == "Deny"
    ])
    error_message = "Bucket policy must deny non-TLS access."
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.kms[0].statement :
      st.sid == "CloudWatchLogs" && contains(flatten([for p in st.principals : p.identifiers]), "logs.us-gov-west-1.amazonaws.com")
    ])
    error_message = "KMS key must grant the regional (partition-aware) CloudWatch Logs principal."
  }
}

run "rejects_invalid_retention" {
  command = plan

  variables {
    log_retention_days = 42
  }

  expect_failures = [var.log_retention_days]
}
