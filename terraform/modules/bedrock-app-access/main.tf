data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  foundation_model_arns = [
    for id in var.foundation_model_ids : "arn:${local.partition}:bedrock:${local.region}::foundation-model/${id}"
  ]

  inference_profile_arns = [
    for id in var.inference_profile_ids : "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:inference-profile/${id}"
  ]

  # A cross-region profile routes to the same model in several regions, so the
  # underlying model is granted in any region. The profile ARN is still the gate.
  profile_model_arns = [
    for id in var.inference_profile_ids : "arn:${local.partition}:bedrock:*::foundation-model/${replace(id, "/^[a-z-]+\\./", "")}"
  ]

  model_arns = distinct(concat(local.foundation_model_arns, local.inference_profile_arns, local.profile_model_arns))

  guardrail_condition = var.guardrail_version == null ? {
    test   = "StringLike"
    values = [var.guardrail_arn, "${var.guardrail_arn}:*"]
    } : {
    test   = "StringEquals"
    values = ["${var.guardrail_arn}:${var.guardrail_version}"]
  }

  invoke_actions = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
}

data "aws_iam_policy_document" "this" {
  statement {
    sid       = "InvokeApprovedModels"
    actions   = local.invoke_actions
    resources = local.model_arns
  }

  # Explicit deny wins over any Allow elsewhere (e.g. a broad managed policy on
  # the same role), so no request to these models can skip the guardrail.
  statement {
    sid       = "DenyInvokeWithoutGuardrail"
    effect    = "Deny"
    actions   = local.invoke_actions
    resources = local.model_arns
    condition {
      test     = local.guardrail_condition.test == "StringLike" ? "StringNotLike" : "StringNotEquals"
      variable = "bedrock:GuardrailIdentifier"
      values   = local.guardrail_condition.values
    }
  }

  statement {
    sid       = "ApplyGuardrail"
    actions   = ["bedrock:ApplyGuardrail"]
    resources = [var.guardrail_arn]
  }

  dynamic "statement" {
    for_each = length(var.knowledge_base_arns) > 0 ? [1] : []
    content {
      sid       = "RetrieveFromKnowledgeBases"
      actions   = ["bedrock:Retrieve"]
      resources = var.knowledge_base_arns
    }
  }
}

resource "aws_iam_policy" "this" {
  name        = var.name
  description = "Least-privilege Bedrock access for a RAG application: approved models only, guardrail enforced."
  policy      = data.aws_iam_policy_document.this.json
  tags        = var.tags

  lifecycle {
    precondition {
      condition     = length(local.model_arns) > 0
      error_message = "Set at least one of foundation_model_ids or inference_profile_ids."
    }
  }
}

resource "aws_iam_role_policy_attachment" "this" {
  count = var.role_name == null ? 0 : 1

  role       = var.role_name
  policy_arn = aws_iam_policy.this.arn
}
