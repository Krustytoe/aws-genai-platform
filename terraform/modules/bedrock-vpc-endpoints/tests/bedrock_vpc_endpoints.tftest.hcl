# Offline unit tests: `terraform test` against a mocked provider, no AWS credentials required.

mock_provider "aws" {
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
  name                = "platform-prod"
  vpc_id              = "vpc-0123456789abcdef0"
  subnet_ids          = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  allowed_cidr_blocks = ["10.20.0.0/16"]
}

run "creates_runtime_endpoints_with_private_dns" {
  command = plan

  assert {
    condition     = aws_vpc_endpoint.this["bedrock-runtime"].service_name == "com.amazonaws.us-gov-west-1.bedrock-runtime"
    error_message = "Service name must be built from the current region."
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.this : e.private_dns_enabled && e.vpc_endpoint_type == "Interface"])
    error_message = "Endpoints must be Interface type with private DNS."
  }

  assert {
    condition     = length(aws_vpc_endpoint.this) == 2
    error_message = "Default should create bedrock-runtime and bedrock-agent-runtime."
  }
}

run "endpoint_policy_limits_to_account" {
  command = plan

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.endpoint.statement[0].condition :
      c.variable == "aws:PrincipalAccount" && contains(c.values, "111111111111")
    ])
    error_message = "Endpoint policy must restrict principals to this account."
  }
}

run "org_scope" {
  command = plan

  variables {
    allowed_principal_org_id = "o-abc123def4"
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.endpoint.statement[0].condition :
      c.variable == "aws:PrincipalOrgID" && contains(c.values, "o-abc123def4")
    ])
    error_message = "Endpoint policy should switch to the org condition."
  }
}

run "rejects_open_cidr" {
  command = plan

  variables {
    allowed_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_cidr_blocks]
}

run "requires_some_caller" {
  command = plan

  variables {
    allowed_cidr_blocks = []
  }

  expect_failures = [aws_vpc_endpoint.this]
}
