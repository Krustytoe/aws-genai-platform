# Offline unit tests: `terraform test` against a mocked provider, no AWS credentials required.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws-us-gov"
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
}

variables {
  name                  = "rag-api-bedrock"
  inference_profile_ids = ["us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0"]
  guardrail_arn         = "arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:guardrail/abc123def456"
  knowledge_base_arns   = ["arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:knowledge-base/KB12345678"]
}

run "grants_profile_and_underlying_model" {
  command = plan

  assert {
    condition     = contains(output.model_arns, "arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:inference-profile/us-gov.anthropic.claude-sonnet-4-5-20250929-v1:0")
    error_message = "Inference profile ARN must be granted."
  }

  assert {
    condition     = contains(output.model_arns, "arn:aws-us-gov:bedrock:*::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0")
    error_message = "Underlying model must be granted with the geo prefix stripped."
  }

  assert {
    condition     = length([for a in output.model_arns : a if a == "*"]) == 0
    error_message = "Model grants must never be a bare wildcard."
  }
}

run "guardrail_is_enforced_by_explicit_deny" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.this.statement :
      st.sid == "DenyInvokeWithoutGuardrail" && st.effect == "Deny" && anytrue([
        for c in st.condition : c.variable == "bedrock:GuardrailIdentifier" && c.test == "StringNotLike"
      ])
    ])
    error_message = "Invocations without the guardrail must be explicitly denied."
  }
}

run "pinned_guardrail_version" {
  command = plan

  variables {
    guardrail_version = "3"
  }

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.this.statement :
      st.sid == "DenyInvokeWithoutGuardrail" && anytrue([
        for c in st.condition : c.test == "StringNotEquals" && contains(c.values, "arn:aws-us-gov:bedrock:us-gov-west-1:111111111111:guardrail/abc123def456:3")
      ])
    ])
    error_message = "A pinned version should switch to an exact-match condition on arn:version."
  }
}

run "retrieve_scoped_to_knowledge_bases" {
  command = plan

  assert {
    condition = anytrue([
      for st in data.aws_iam_policy_document.this.statement :
      st.sid == "RetrieveFromKnowledgeBases" && contains(st.resources, var.knowledge_base_arns[0])
    ])
    error_message = "bedrock:Retrieve must be scoped to the listed knowledge bases."
  }
}

run "attaches_when_role_given" {
  command = plan

  variables {
    role_name = "rag-api-task"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 1
    error_message = "Policy should attach to the supplied role."
  }
}

run "requires_at_least_one_model" {
  command = plan

  variables {
    inference_profile_ids = []
  }

  expect_failures = [aws_iam_policy.this]
}

run "rejects_malformed_profile_id" {
  command = plan

  variables {
    inference_profile_ids = ["claude"]
  }

  expect_failures = [var.inference_profile_ids]
}
