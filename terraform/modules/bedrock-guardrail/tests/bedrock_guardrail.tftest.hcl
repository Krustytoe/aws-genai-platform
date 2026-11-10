# Offline unit tests: `terraform test` against a mocked provider, no AWS credentials required.

mock_provider "aws" {}

variables {
  name = "rag-baseline"
}

run "secure_defaults" {
  command = plan

  assert {
    condition = alltrue([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config :
      f.input_strength == "HIGH" if f.type != "PROMPT_ATTACK"
    ])
    error_message = "Harm filters should default to HIGH."
  }

  assert {
    condition = anytrue([
      for f in aws_bedrock_guardrail.this.content_policy_config[0].filters_config :
      f.type == "PROMPT_ATTACK" && f.input_strength == "HIGH" && f.output_strength == "NONE"
    ])
    error_message = "Prompt-attack filter must be HIGH on input and NONE on output."
  }

  assert {
    condition = anytrue([
      for p in aws_bedrock_guardrail.this.sensitive_information_policy_config[0].pii_entities_config :
      p.type == "US_SOCIAL_SECURITY_NUMBER" && p.action == "BLOCK"
    ])
    error_message = "SSNs should be blocked by default."
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.contextual_grounding_policy_config[0].filters_config) == 2
    error_message = "Grounding and relevance checks should both be on by default."
  }

  assert {
    condition     = length(aws_bedrock_guardrail_version.this) == 1
    error_message = "A version should be published by default."
  }
}

run "denied_topics_render" {
  command = plan

  variables {
    denied_topics = [{
      name       = "InvestmentAdvice"
      definition = "Recommendations about buying or selling specific securities."
      examples   = ["Should I buy ACME stock?"]
    }]
  }

  assert {
    condition     = aws_bedrock_guardrail.this.topic_policy_config[0].topics_config[0].type == "DENY"
    error_message = "Denied topics must use type DENY."
  }
}

run "grounding_can_be_disabled" {
  command = plan

  variables {
    grounding_threshold = null
    relevance_threshold = null
    publish_version     = false
  }

  assert {
    condition     = length(aws_bedrock_guardrail.this.contextual_grounding_policy_config) == 0
    error_message = "No grounding block should render when both thresholds are null."
  }

  assert {
    condition     = output.guardrail_version == "DRAFT"
    error_message = "Unpublished guardrails should report DRAFT."
  }
}

run "rejects_invalid_pii_action" {
  command = plan

  variables {
    pii_entities = { EMAIL = "LOG" }
  }

  expect_failures = [var.pii_entities]
}

run "rejects_invalid_strength" {
  command = plan

  variables {
    content_filter_strength = "MAXIMUM"
  }

  expect_failures = [var.content_filter_strength]
}
