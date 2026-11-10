# bedrock-app-access

## Requirements

Terraform >= 1.7, AWS provider >= 6.0. Run `terraform test` for offline validation (no AWS credentials required).

An IAM managed policy for a RAG application: invoke **only approved models**, **only with the guardrail attached**, and retrieve only from the listed knowledge bases.

## Gotchas this module handles

- **Guardrails enforced by IAM, not by app code.** `bedrock:GuardrailIdentifier` is checked in an **explicit Deny**. A request without the guardrail fails even if another policy on the role (e.g. a broad managed policy) allows `bedrock:*`.
- **Cross-region inference profiles need two grants.** Invoking `us.anthropic.claude-...` requires the inference-profile ARN *and* the underlying foundation-model ARN in every region the profile routes to. The module derives both from the profile ID.
- **No wildcards.** Model access is a list of concrete ARNs, so adding a model is a reviewed change.

## Usage

```hcl
module "app_access" {
  source = "git::https://github.com/Krustytoe/aws-genai-platform.git//terraform/modules/bedrock-app-access?ref=v0.1.0" # x-release-please-version

  name                  = "rag-api-bedrock"
  inference_profile_ids = ["us.anthropic.claude-sonnet-4-5-20250929-v1:0"]
  guardrail_arn         = module.guardrail.guardrail_arn
  guardrail_version     = module.guardrail.guardrail_version
  knowledge_base_arns   = [module.kb.knowledge_base_arn]
  role_name             = aws_iam_role.task.name
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Name of the IAM managed policy. | n/a (required) |
| `foundation_model_ids` | Foundation models the app may invoke directly in this region, e.g. "amazon.nova-pro-v1:0". | `[]` |
| `inference_profile_ids` | Cross-region inference profiles the app may invoke, e.g. "us.anthropic.claude-sonnet-4-5-20250929-v1:0". Grants the profile plus the underlying model in the regions the profile routes to. | `[]` |
| `guardrail_arn` | Guardrail every model invocation must carry. Enforced with an explicit Deny so it holds even if another policy grants broader Bedrock access. | n/a (required) |
| `guardrail_version` | Pin invocations to one guardrail version (e.g. "3"). null allows any published version or DRAFT of the guardrail. | `null` |
| `knowledge_base_arns` | Knowledge bases the app may query with bedrock:Retrieve. | `[]` |
| `role_name` | Existing IAM role to attach the policy to, e.g. the ECS task role. null only creates the policy. | `null` |
| `tags` | Tags applied to the policy. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `policy_arn` | ARN of the managed policy. |
| `policy_json` | Rendered policy document, handy for review in plan output. |
| `model_arns` | Every model and inference-profile ARN the policy grants. |
