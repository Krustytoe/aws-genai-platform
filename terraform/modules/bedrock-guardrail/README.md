# bedrock-guardrail

## Requirements

Terraform >= 1.7, AWS provider >= 6.0. Run `terraform test` for offline validation (no AWS credentials required).

A Bedrock guardrail with an enterprise baseline: harm filters, prompt-attack detection, PII blocking/masking, denied topics and contextual grounding checks, published as an immutable version.

## Gotchas this module handles

- **`PROMPT_ATTACK` is input-only.** Bedrock rejects the filter unless `output_strength = "NONE"`. The module sets it for you so that the jailbreak filter can't be misconfigured.
- **Apps should never run on `DRAFT`.** Any console edit to a draft guardrail changes production behaviour right away. With `publish_version = true` (the default), the module cuts an immutable version, and `skip_destroy` keeps older versions around so pinned apps keep working during a rollout.
- **Grounding needs the app's cooperation.** The grounding/relevance thresholds only work if the caller tags the context as `grounding_source` and the question as `query`. The RAG API in `app/` does this.

## Usage

```hcl
module "guardrail" {
  source = "git::https://github.com/Krustytoe/aws-genai-platform.git//terraform/modules/bedrock-guardrail?ref=v0.1.0" # x-release-please-version

  name = "handbook-baseline"
  denied_topics = [{
    name       = "LegalAdvice"
    definition = "Requests for legal advice about a specific personal situation."
  }]
}
```

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Guardrail name. Also used as the version description prefix. | n/a (required) |
| `description` | Human-readable description shown in the Bedrock console. | `"Enterprise baseline guardrail: content filters, prompt-attack detection, PII handling, grounding checks."` |
| `blocked_input_messaging` | Message returned to the caller when the guardrail blocks the prompt. | `"Sorry, I can't help with that request."` |
| `blocked_outputs_messaging` | Message returned to the caller when the guardrail blocks the model response. | `"Sorry, I can't share that response."` |
| `content_filter_strength` | Strength applied to the SEXUAL, VIOLENCE, HATE, INSULTS and MISCONDUCT filters on both input and output. One of NONE, LOW, MEDIUM, HIGH. | `"HIGH"` |
| `prompt_attack_strength` | Strength of the PROMPT_ATTACK (jailbreak / prompt-injection) input filter. Secure default HIGH; NONE disables it. | `"HIGH"` |
| `pii_entities` | PII entity types and the action to take (BLOCK or ANONYMIZE). Defaults block credentials and government/financial identifiers and mask contact details. | see variables.tf |
| `denied_topics` | Topics the assistant must refuse, e.g. investment or legal advice. Each needs a name (<=100 chars) and a definition (<=200 chars). | `[]` |
| `grounding_threshold` | Contextual grounding threshold (0-0.99). Responses scoring below it are blocked as likely hallucinations. null disables the check. | `0.75` |
| `relevance_threshold` | Contextual relevance threshold (0-0.99). Responses that don't answer the query are blocked. null disables the check. | `0.75` |
| `kms_key_arn` | Customer managed KMS key used to encrypt the guardrail. null uses an AWS owned key. | `null` |
| `publish_version` | Publish an immutable guardrail version. Applications should pin a version, not DRAFT, so a console edit can't change production behaviour. | `true` |
| `tags` | Tags applied to every resource. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `guardrail_id` | Guardrail ID, passed to Converse as guardrailIdentifier. |
| `guardrail_arn` | Guardrail ARN, used in IAM bedrock:GuardrailIdentifier conditions. |
| `guardrail_version` | Published version to pin in the application, or DRAFT when publish_version is false. |
