# CloudTrail, its S3 destination, and a CloudWatch log group so alarms have
# something to filter.
#
# The trail is multi-region and includes global service events. A single-region
# trail is a blind spot: an attacker who knows which region you watch simply
# uses another one.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Destination bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "trail" {
  bucket = var.bucket_name

  # An audit trail you can delete by accident is not an audit trail.
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

    # Cuts KMS request cost by reusing a data key across objects in the bucket.
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
    # ACLs disabled entirely. Object ownership is the account, so a
    # misconfigured ACL cannot expose anything.
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "transition-and-expire"
    status = "Enabled"

    filter {}

    # An interrupted upload leaves parts that are billed but invisible in the
    # object listing. Without this they accumulate forever.
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

    # Without this condition the bucket would accept deliveries from any
    # account's trail, which is a confused deputy waiting to happen.
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

# ---------------------------------------------------------------------------
# CloudWatch Logs destination
#
# S3 is the durable copy; CloudWatch is what metric filters and alarms can
# actually read in near real time.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# The trail
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "this" {
  #checkov:skip=CKV_AWS_252: sns_topic_name fires once per delivered log file, which is noise rather than signal. Detection runs off the CloudWatch log group below, through the metric filters and alarms in modules/alerting.
  name           = var.name
  s3_bucket_name = aws_s3_bucket.trail.id

  # Without this an attacker can cover their tracks in one region.
  is_multi_region_trail = true

  # IAM and other global services report into one region only. Without this,
  # those events are simply absent.
  include_global_service_events = true

  # Signs each log file so tampering after delivery is detectable.
  enable_log_file_validation = true

  kms_key_id = var.kms_key_arn

  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.trail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.trail_to_logs.arn

  # Data events for S3 objects. Management events alone record that a bucket
  # was created, not that its contents were read.
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
