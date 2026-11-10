data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  region     = data.aws_region.current.region
  account_id = data.aws_caller_identity.current.account_id

  principal_condition = var.allowed_principal_org_id == null ? {
    variable = "aws:PrincipalAccount"
    value    = local.account_id
    } : {
    variable = "aws:PrincipalOrgID"
    value    = var.allowed_principal_org_id
  }
}

resource "aws_security_group" "this" {
  name        = "${var.name}-bedrock-endpoints"
  description = "HTTPS from approved callers to Bedrock interface endpoints"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-bedrock-endpoints" })
  # No egress rules: Terraform strips the AWS default allow-all, and interface
  # endpoints don't need to initiate connections.
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "HTTPS from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "sg" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "HTTPS from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = each.value
}

# Endpoint policy: callers from outside the account (or org) can't use our
# network path to reach Bedrock, even with valid credentials.
data "aws_iam_policy_document" "endpoint" {
  statement {
    sid       = "AllowOwnPrincipalsOnly"
    actions   = ["*"]
    resources = ["*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringEquals"
      variable = local.principal_condition.variable
      values   = [local.principal_condition.value]
    }
  }
}

resource "aws_vpc_endpoint" "this" {
  for_each = toset(var.services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subnet_ids
  security_group_ids  = [aws_security_group.this.id]
  private_dns_enabled = true
  policy              = data.aws_iam_policy_document.endpoint.json
  tags                = merge(var.tags, { Name = "${var.name}-${each.value}" })

  lifecycle {
    precondition {
      condition     = length(var.allowed_cidr_blocks) + length(var.allowed_security_group_ids) > 0
      error_message = "Set allowed_cidr_blocks or allowed_security_group_ids, otherwise nothing can reach the endpoints."
    }
  }
}
