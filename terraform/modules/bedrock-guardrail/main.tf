locals {
  harm_filters = ["SEXUAL", "VIOLENCE", "HATE", "INSULTS", "MISCONDUCT"]

  grounding_filters = merge(
    var.grounding_threshold == null ? {} : { GROUNDING = var.grounding_threshold },
    var.relevance_threshold == null ? {} : { RELEVANCE = var.relevance_threshold },
  )
}

resource "aws_bedrock_guardrail" "this" {
  name                      = var.name
  description               = var.description
  blocked_input_messaging   = var.blocked_input_messaging
  blocked_outputs_messaging = var.blocked_outputs_messaging
  kms_key_arn               = var.kms_key_arn
  tags                      = var.tags

  content_policy_config {
    dynamic "filters_config" {
      for_each = toset(local.harm_filters)
      content {
        type            = filters_config.value
        input_strength  = var.content_filter_strength
        output_strength = var.content_filter_strength
      }
    }

    # Prompt attacks only apply to input; Bedrock requires output_strength NONE.
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = var.prompt_attack_strength
      output_strength = "NONE"
    }
  }

  dynamic "sensitive_information_policy_config" {
    for_each = length(var.pii_entities) > 0 ? [1] : []
    content {
      dynamic "pii_entities_config" {
        for_each = var.pii_entities
        content {
          type   = pii_entities_config.key
          action = pii_entities_config.value
        }
      }
    }
  }

  dynamic "topic_policy_config" {
    for_each = length(var.denied_topics) > 0 ? [1] : []
    content {
      dynamic "topics_config" {
        for_each = var.denied_topics
        content {
          name       = topics_config.value.name
          definition = topics_config.value.definition
          examples   = topics_config.value.examples
          type       = "DENY"
        }
      }
    }
  }

  dynamic "contextual_grounding_policy_config" {
    for_each = length(local.grounding_filters) > 0 ? [1] : []
    content {
      dynamic "filters_config" {
        for_each = local.grounding_filters
        content {
          type      = filters_config.key
          threshold = filters_config.value
        }
      }
    }
  }
}

resource "aws_bedrock_guardrail_version" "this" {
  count = var.publish_version ? 1 : 0

  guardrail_arn = aws_bedrock_guardrail.this.guardrail_arn
  description   = "${var.name} published by Terraform"

  # Keep old versions so apps pinned to them keep working through a rollout.
  skip_destroy = true
}
