data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_s3_bucket" "trail" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }

    dynamic "expiration" {
      for_each = var.s3_expiration_days > 0 ? [1] : []

      content {
        days = var.s3_expiration_days
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    # Without this the bucket accepts deliveries from any account's trail.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:*:${data.aws_caller_identity.current.account_id}:trail/${var.name}"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.trail.arn,
      "${aws_s3_bucket.trail.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

# S3 is the durable copy. CloudWatch is what metric filters can read.
resource "aws_cloudwatch_log_group" "trail" {
  name              = "/aws/cloudtrail/${var.name}"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-cloudtrail" })
}

data "aws_iam_policy_document" "trail_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "trail_to_logs" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.trail.arn}:*"]
  }
}

resource "aws_iam_role" "trail_to_logs" {
  name_prefix        = "${var.name}-cloudtrail-"
  assume_role_policy = data.aws_iam_policy_document.trail_assume.json

  tags = merge(var.tags, { Name = "${var.name}-cloudtrail" })
}

resource "aws_iam_role_policy" "trail_to_logs" {
  name_prefix = "${var.name}-cloudtrail-"
  role        = aws_iam_role.trail_to_logs.id
  policy      = data.aws_iam_policy_document.trail_to_logs.json
}

resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_252: sns_topic_name fires per delivered file; detection runs off the log group instead
  name           = var.name
  s3_bucket_name = aws_s3_bucket.trail.id

  is_multi_region_trail = true

  # IAM and other global services report into one region only.
  include_global_service_events = true

  enable_log_file_validation = true

  kms_key_id = var.kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_logs.arn

  # Management events alone record that a bucket was created, not that its
  # contents were read.
  advanced_event_selector {
    name = "S3 object access"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
  }

  advanced_event_selector {
    name = "All management events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  tags = merge(var.tags, { Name = var.name })

  depends_on = [aws_s3_bucket_policy.trail]
}
