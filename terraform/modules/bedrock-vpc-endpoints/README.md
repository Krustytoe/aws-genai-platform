# bedrock-vpc-endpoints

## Requirements

Terraform >= 1.7, AWS provider >= 6.0. Run `terraform test` for offline validation (no AWS credentials required).

Interface VPC endpoints for Bedrock (`bedrock-runtime`, `bedrock-agent-runtime` by default), so prompts and responses never cross the public internet, plus an endpoint policy that only admits your own principals.

## Gotchas this module handles

- **Two runtimes.** `Converse`/`InvokeModel` go through `bedrock-runtime`, and knowledge base `Retrieve` goes through `bedrock-agent-runtime`. A RAG app needs both, or it quietly falls back to the public endpoint through NAT.
- **Data-exfiltration path.** Without an endpoint policy, anyone with credentials from *any* account could use your endpoint. The policy requires `aws:PrincipalAccount` (or `aws:PrincipalOrgID`).
- **Least-open security group.** Ingress is 443 from named CIDRs or security groups only, `0.0.0.0/0` is rejected, and there are no egress rules.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name` | Name prefix for the endpoints and their security group. | n/a (required) |
| `vpc_id` | VPC to create the interface endpoints in. | n/a (required) |
| `subnet_ids` | Private subnets for the endpoint ENIs, one per AZ for availability. | n/a (required) |
| `allowed_cidr_blocks` | CIDRs allowed to reach the endpoints on 443. | `[]` |
| `allowed_security_group_ids` | Security groups (e.g. the app's ECS service SG) allowed to reach the endpoints on 443. | `[]` |
| `services` | Bedrock service endpoints to create. bedrock-runtime serves InvokeModel/Converse; bedrock-agent-runtime serves knowledge base Retrieve. | `["bedrock-runtime", "bedrock-agent-runtime"]` |
| `allowed_principal_org_id` | If set, the endpoint policy allows principals from this AWS Organization instead of only this account. | `null` |
| `tags` | Tags applied to every resource. | `{}` |

## Outputs

| Name | Description |
|---|---|
| `endpoint_ids` | Map of service name to VPC endpoint ID. |
| `security_group_id` | Security group attached to the endpoints. |
