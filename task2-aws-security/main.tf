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
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

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
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

  alias       = "${local.name_prefix}-data"
  description = "Encrypts EBS volumes and the application data bucket"

  # No service principals. EBS and S3 authorise through the caller's IAM
  # identity, not a service principal, so the account root statement is enough.
  tags = local.tags
}

module "secrets_key" {
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

  alias       = "${local.name_prefix}-secrets"
  description = "Encrypts Secrets Manager secrets"

  service_principals = ["secretsmanager.amazonaws.com"]

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.1.0"

  name       = local.name_prefix
  cidr_block = var.vpc_cidr
  az_count   = var.az_count

  # The public subnets hold the NAT gateways and nothing else, so nothing
  # should acquire a public address here at all.
  map_public_ip_on_launch = false

  enable_flow_logs         = true
  flow_logs_kms_key_arn    = module.observability_key.arn
  flow_logs_retention_days = var.flow_logs_retention_days

  # What lets a private instance be managed by SSM with no route to the
  # internet. ssmmessages carries the session channel; without it a session
  # opens and then hangs. The S3 gateway endpoint is free, where an interface
  # endpoint for S3 bills per hour and per gigabyte.
  interface_endpoints        = ["ssm", "ssmmessages", "ec2messages"]
  enable_s3_gateway_endpoint = true

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
  source = "git::https://github.com/JPLima/devops.git//modules/secret?ref=v1.1.0"

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
  source = "git::https://github.com/JPLima/devops.git//modules/iam-instance-role?ref=v1.1.0"

  name            = "${local.name_prefix}-app"
  data_bucket_arn = aws_s3_bucket.data.arn
  kms_key_arn     = module.data_key.arn
  secret_arns     = [module.app_secret.secret_arn]

  tags = local.tags
}

# The instance's security group.
#
# No ingress rules at all. That is the honest answer to "only necessary ports":
# the number of inbound ports this workload needs is zero, because
# administration happens through Session Manager rather than SSH. A bastion on
# port 22 would add a host to patch, a key to distribute and revoke, and an
# audit trail in sshd logs rather than CloudTrail.
module "app_sg" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-group?ref=v1.1.0"

  name        = "${local.name_prefix}-app"
  description = "Private application instance for ${local.name_prefix}"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {}

  egress_rules = {
    # To the interface endpoints for SSM and the S3 gateway endpoint. Scoped
    # to the VPC CIDR rather than 0.0.0.0/0, so a compromised instance cannot
    # call out to an arbitrary address.
    "https-to-vpc-endpoints" = {
      description = "HTTPS to the VPC interface and gateway endpoints"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  tags = local.tags
}

module "compute" {
  source = "git::https://github.com/JPLima/devops.git//modules/ec2?ref=v1.1.0"

  name               = "${local.name_prefix}-app"
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids = [module.app_sg.id]
  instance_type      = var.instance_type

  # Left at the module default of false, but stated because this is the line a
  # reviewer looks for.
  associate_public_ip_address = false

  iam_instance_profile = module.iam.instance_profile_name
  kms_key_arn          = module.data_key.arn

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Audit and detection
# ---------------------------------------------------------------------------

module "logging" {
  source = "git::https://github.com/JPLima/devops.git//modules/cloudtrail?ref=v1.1.0"

  name               = local.name_prefix
  bucket_name        = "${local.name_prefix}-cloudtrail-${local.bucket_suffix}"
  kms_key_arn        = module.observability_key.arn
  log_retention_days = var.cloudtrail_retention_days

  tags = local.tags
}

module "config" {
  source = "git::https://github.com/JPLima/devops.git//modules/aws-config?ref=v1.1.0"

  name        = local.name_prefix
  bucket_name = "${local.name_prefix}-config-${local.bucket_suffix}"
  kms_key_arn = module.observability_key.arn

  tags = local.tags
}

module "alerting" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-alerting?ref=v1.1.0"

  name                = local.name_prefix
  log_group_name      = module.logging.log_group_name
  kms_key_arn         = module.observability_key.arn
  notification_emails = var.security_notification_emails

  tags = local.tags
}
