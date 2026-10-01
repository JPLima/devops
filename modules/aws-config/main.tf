data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_s3_bucket" "config" {
  bucket = var.bucket_name

  tags = merge(var.tags, { Name = var.bucket_name })
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket = aws_s3_bucket.config.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-snapshots"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = var.expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.config]
}

data "aws_iam_policy_document" "config_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
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
      aws_s3_bucket.config.arn,
      "${aws_s3_bucket.config.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config_bucket.json
}

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "config" {
  name_prefix        = "${var.name}-config-"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  tags = merge(var.tags, { Name = "${var.name}-config" })
}

# Config needs read access to every resource type it records, and that list
# changes whenever AWS adds a service.
resource "aws_iam_role_policy_attachment" "config" {
  role       = aws_iam_role.config.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

data "aws_iam_policy_document" "config_delivery" {
  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.config.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.config.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "config_delivery" {
  name_prefix = "${var.name}-delivery-"
  role        = aws_iam_role.config.id
  policy      = data.aws_iam_policy_document.config_delivery.json
}

resource "aws_config_configuration_recorder" "this" {
  name     = var.name
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = var.name
  s3_bucket_name = aws_s3_bucket.config.id
  s3_key_prefix  = "AWSLogs/${data.aws_caller_identity.current.account_id}/Config"

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [
    aws_config_configuration_recorder.this,
    aws_s3_bucket_policy.config,
  ]
}

# Creating a recorder does not start it. Without this, Config records nothing
# and every rule reports NOT_APPLICABLE.
resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.this]
}

locals {
  # The root account cannot be disabled through any API. The first two rules
  # plus the root-account-usage alarm are the part that is codifiable.
  rules = {
    "root-account-mfa-enabled"     = "ROOT_ACCOUNT_MFA_ENABLED"
    "root-access-key-check"        = "IAM_ROOT_ACCESS_KEY_CHECK"
    "iam-user-mfa-enabled"         = "IAM_USER_MFA_ENABLED"
    "encrypted-volumes"            = "ENCRYPTED_VOLUMES"
    "ec2-imdsv2-check"             = "EC2_IMDSV2_CHECK"
    "ec2-no-public-ip"             = "EC2_INSTANCE_NO_PUBLIC_IP"
    "rds-storage-encrypted"        = "RDS_STORAGE_ENCRYPTED"
    "rds-not-public"               = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
    "s3-encryption-enabled"        = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
    "s3-public-read-prohibited"    = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
    "s3-public-write-prohibited"   = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
    "s3-ssl-requests-only"         = "S3_BUCKET_SSL_REQUESTS_ONLY"
    "cloudtrail-enabled"           = "CLOUD_TRAIL_ENABLED"
    "cloudtrail-log-validation"    = "CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED"
    "cloudtrail-encryption"        = "CLOUD_TRAIL_ENCRYPTION_ENABLED"
    "vpc-flow-logs-enabled"        = "VPC_FLOW_LOGS_ENABLED"
    "restricted-ssh"               = "INCOMING_SSH_DISABLED"
    "sg-no-unrestricted-ingress"   = "VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS"
    "kms-key-rotation-enabled"     = "CMK_BACKING_KEY_ROTATION_ENABLED"
    "secretsmanager-kms-encrypted" = "SECRETSMANAGER_USING_CMK"
  }
}

resource "aws_config_config_rule" "managed" {
  for_each = local.rules

  name = "${var.name}-${each.key}"

  source {
    owner             = "AWS"
    source_identifier = each.value
  }

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })

  depends_on = [aws_config_configuration_recorder_status.this]
}
