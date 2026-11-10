data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  dns_suffix = data.aws_partition.current.dns_suffix
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  bucket_name     = coalesce(var.bucket_name, "bedrock-invocation-logs-${local.account_id}-${local.region}")
  kms_key_arn     = var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn
  bedrock_src_arn = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:*"
  log_group_arn   = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.log_group_name}"
}

# ---------------------------------------------------------------------------
# KMS: one CMK for both the log group and the bucket, usable only by this
# account's CloudWatch Logs group and by Bedrock acting for this account.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  count = var.kms_key_arn == null ? 1 : 0

  statement {
    sid       = "AccountAdmin"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "CloudWatchLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.${local.dns_suffix}"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = [local.log_group_arn]
    }
  }

  statement {
    sid       = "BedrockS3Delivery"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_src_arn]
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  description             = "Bedrock model invocation logs"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = var.tags
}

resource "aws_kms_alias" "this" {
  count = var.kms_key_arn == null ? 1 : 0

  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.this[0].key_id
}

# ---------------------------------------------------------------------------
# CloudWatch Logs: searchable, short-path audit trail.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "this" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = local.kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.${local.dns_suffix}"]
    }
    # Confused-deputy protection: only Bedrock acting for this account can assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_src_arn]
    }
  }
}

data "aws_iam_policy_document" "delivery" {
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:log-stream:*"]
  }

  statement {
    sid       = "WriteLargePayloads"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/large-data/*"]
  }

  statement {
    sid       = "EncryptLargePayloads"
    actions   = ["kms:GenerateDataKey"]
    resources = [local.kms_key_arn]
  }
}

resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "this" {
  name   = "delivery"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.delivery.json
}

# ---------------------------------------------------------------------------
# S3: complete payload archive, the raw material for offline evals.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-invocation-logs"
    status = "Enabled"
    filter {}
    expiration {
      days = var.s3_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "BedrockDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/invocations/*"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.${local.dns_suffix}"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [local.bedrock_src_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Account/region singleton: Bedrock allows one logging configuration per region.
# ---------------------------------------------------------------------------

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    text_data_delivery_enabled      = var.deliver_text_data
    image_data_delivery_enabled     = var.deliver_image_data
    embedding_data_delivery_enabled = var.deliver_embedding_data
    video_data_delivery_enabled     = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.this.name
      role_arn       = aws_iam_role.this.arn

      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.this.id
        key_prefix  = "large-data"
      }
    }

    s3_config {
      bucket_name = aws_s3_bucket.this.id
      key_prefix  = "invocations"
    }
  }

  depends_on = [
    aws_s3_bucket_policy.this,
    aws_iam_role_policy.this,
  ]
}
