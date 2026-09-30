# Task 2 root module.
#
# A private workload with the security controls the challenge asks for:
# segmented network, no inbound access, least-privilege IAM, encryption
# everywhere, an audit trail, configuration recording, and alarms that fire on
# the events worth waking someone for.

# ---------------------------------------------------------------------------
# Encryption keys
#
# Three keys rather than one. A key per purpose means the key policy stays
# readable and revoking access to logs does not also lock out the workload.
# ---------------------------------------------------------------------------

module "observability_key" {
  source = "../modules/kms-key"

  alias       = "${local.name_prefix}-observability"
  description = "Encrypts CloudTrail, VPC flow logs and AWS Config data"

  service_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "logs.${var.region}.amazonaws.com",
    "delivery.logs.amazonaws.com",
  ]

  tags = local.tags
}

module "data_key" {
  source = "../modules/kms-key"

  alias       = "${local.name_prefix}-data"
  description = "Encrypts EBS volumes and the application data bucket"

  # No service principals. EBS and S3 authorise through the caller's IAM
  # identity, not a service principal, so the account root statement is enough.
  tags = local.tags
}

module "secrets_key" {
  source = "../modules/kms-key"

  alias       = "${local.name_prefix}-secrets"
  description = "Encrypts Secrets Manager secrets"

  service_principals = ["secretsmanager.amazonaws.com"]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "network" {
  source = "./modules/network"

  name       = local.name_prefix
  cidr_block = var.vpc_cidr
  az_count   = var.az_count

  flow_logs_kms_key_arn    = module.observability_key.arn
  flow_logs_retention_days = var.flow_logs_retention_days

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Application data bucket
#
# The one bucket the instance role can touch. Everything the challenge asks
# for on storage encryption is here: SSE-KMS with a customer-managed key,
# versioning, public access blocked, ACLs disabled, and TLS enforced.
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "data" {
  bucket = "${local.name_prefix}-data-${local.bucket_suffix}"

  tags = merge(local.tags, { Name = "${local.name_prefix}-data" })
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.data_key.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "data_bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.data.arn,
      "${aws_s3_bucket.data.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Encryption at rest is configured by default on the bucket, but a client can
  # still ask for a different algorithm. This refuses anything but our key.
  statement {
    sid    = "DenyWrongEncryption"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/*"]

    condition {
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
      values   = [module.data_key.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "data" {
  bucket = aws_s3_bucket.data.id
  policy = data.aws_iam_policy_document.data_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.data]
}

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------

module "app_secret" {
  source = "./modules/secrets"

  name        = "${local.name_prefix}/application/database"
  description = "Database credential for the ${local.name_prefix} application"
  username    = "appuser"
  kms_key_arn = module.secrets_key.arn

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Identity and compute
# ---------------------------------------------------------------------------

module "iam" {
  source = "./modules/iam"

  name            = "${local.name_prefix}-app"
  data_bucket_arn = aws_s3_bucket.data.arn
  kms_key_arn     = module.data_key.arn
  secret_arns     = [module.app_secret.secret_arn]

  tags = local.tags
}

module "compute" {
  source = "./modules/compute"

  name                  = "${local.name_prefix}-app"
  vpc_id                = module.network.vpc_id
  vpc_cidr_block        = module.network.vpc_cidr_block
  subnet_id             = module.network.private_subnet_ids[0]
  instance_type         = var.instance_type
  instance_profile_name = module.iam.instance_profile_name
  kms_key_arn           = module.data_key.arn

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Audit and detection
# ---------------------------------------------------------------------------

module "logging" {
  source = "./modules/logging"

  name               = local.name_prefix
  bucket_name        = "${local.name_prefix}-cloudtrail-${local.bucket_suffix}"
  kms_key_arn        = module.observability_key.arn
  log_retention_days = var.cloudtrail_retention_days

  tags = local.tags
}

module "config" {
  source = "./modules/config"

  name        = local.name_prefix
  bucket_name = "${local.name_prefix}-config-${local.bucket_suffix}"
  kms_key_arn = module.observability_key.arn

  tags = local.tags
}

module "alerting" {
  source = "./modules/alerting"

  name                = local.name_prefix
  log_group_name      = module.logging.log_group_name
  kms_key_arn         = module.observability_key.arn
  notification_emails = var.security_notification_emails

  tags = local.tags
}
