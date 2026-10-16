data "aws_caller_identity" "workload" {}

locals {
  account_id  = data.aws_caller_identity.workload.account_id
  bucket_name = "${var.name_prefix}-invocation-logs-${local.account_id}-${var.region}"
}

# --- S3: long-term log storage -------------------------------------------

resource "aws_s3_bucket" "logs" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "logs" {
  bucket = aws_s3_bucket.logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = var.log_retention_days
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }
}

data "aws_iam_policy_document" "logs_bucket" {
  # Bedrock may only write objects, and only for this account and region.
  statement {
    sid       = "AllowBedrockLogDelivery"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${local.account_id}:*"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]

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
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = data.aws_iam_policy_document.logs_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# --- CloudWatch Logs: searchable, short-term -----------------------------

resource "aws_cloudwatch_log_group" "invocations" {
  name              = "/aws/bedrock/${var.name_prefix}/invocations"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "bedrock_logging_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${local.account_id}:*"]
    }
  }
}

resource "aws_iam_role" "bedrock_logging" {
  name               = "${var.name_prefix}-bedrock-logging"
  assume_role_policy = data.aws_iam_policy_document.bedrock_logging_trust.json
}

data "aws_iam_policy_document" "bedrock_logging" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.invocations.arn}:log-stream:*"]
  }
}

resource "aws_iam_role_policy" "bedrock_logging" {
  name   = "write-invocation-logs"
  role   = aws_iam_role.bedrock_logging.id
  policy = data.aws_iam_policy_document.bedrock_logging.json
}

# --- Invocation logging (one per account and region) ---------------------

resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  logging_config {
    text_data_delivery_enabled      = true
    image_data_delivery_enabled     = true
    embedding_data_delivery_enabled = true
    video_data_delivery_enabled     = true

    s3_config {
      bucket_name = aws_s3_bucket.logs.id
      key_prefix  = "invocations"
    }

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.invocations.name
      role_arn       = aws_iam_role.bedrock_logging.arn

      # Large payloads (e.g. images) go to S3 instead of CloudWatch.
      large_data_delivery_s3_config {
        bucket_name = aws_s3_bucket.logs.id
        key_prefix  = "large-payloads"
      }
    }
  }

  depends_on = [
    aws_s3_bucket_policy.logs,
    aws_iam_role_policy.bedrock_logging,
  ]
}
