# Unchanged from the original.
provider "aws" {
  region = "us-east-1"
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# FIX 1. The original hardcoded the bucket name, which is globally unique.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"

  # FIX 2. The original set acl = "private", removed from this resource in
  # provider v5. BucketOwnerEnforced below disables ACLs entirely instead.

  force_destroy = true

  tags = merge(var.tags, { Name = "${var.function_name}-data" })
}

resource "aws_s3_bucket_ownership_controls" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# FIX 8. No versioning, encryption or public access block on the original.
resource "aws_s3_bucket_versioning" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# KMS was already in play through the bucket's encryption, so this is not a
# new service: it replaces the AWS-managed key with one we control.
module "bucket_key" {
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

  alias                   = "${var.function_name}-data"
  description             = "Encrypts objects written by ${var.function_name}, its log group and its environment variables"
  deletion_window_in_days = 7

  # CloudWatch Logs cannot assume a role, so it needs a grant in the key
  # policy. S3 and Lambda go through the account root statement.
  service_principals = ["logs.${data.aws_region.current.region}.amazonaws.com"]

  service_condition = {
    test     = "ArnLike"
    variable = "kms:EncryptionContext:aws:logs:arn"
    values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
  }

  tags = var.tags
}

resource "aws_s3_bucket_server_side_encryption_configuration" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.bucket_key.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    id     = "expire-invocation-records"
    status = "Enabled"

    filter {
      prefix = "invocations/"
    }

    expiration {
      days = 90
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  # No prefix filter: the deployment zip is not under invocations/.
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.my_bucket]
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.my_bucket.arn,
      "${aws_s3_bucket.my_bucket.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.my_bucket]
}

# FIX 3. The original pointed the function at an object nothing created.
# archive_file builds the zip at plan time, from source.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.build/lambda_function_payload.zip"

  output_file_mode = "0644"
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "lambda_function_payload.zip"
  source = data.archive_file.lambda.output_path

  # Without this a code change uploads nothing.
  etag = data.archive_file.lambda.output_md5

  server_side_encryption = "aws:kms"
  kms_key_id             = module.bucket_key.arn

  tags = var.tags

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.my_bucket]
}

resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# FIX 4. The original role had a trust policy and no permissions at all, so
# the function could not even write logs and every failure was invisible.
# Scoped to its own log group rather than AWSLambdaBasicExecutionRole, which
# grants logs:CreateLogGroup on "*".
data "aws_iam_policy_document" "lambda" {
  statement {
    sid    = "WriteOwnLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  statement {
    sid    = "ReadWriteInvocationRecords"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
    ]

    resources = ["${aws_s3_bucket.my_bucket.arn}/invocations/*"]
  }

  # Without this, PutObject on the encrypted bucket returns AccessDenied and
  # the error names S3 rather than KMS.
  statement {
    sid    = "UseBucketKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [module.bucket_key.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.function_name}-policy"
  role   = aws_iam_role.iam_for_lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# Created explicitly: a group Lambda makes on first invocation has no
# retention and cannot be named in an IAM policy at plan time.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  kms_key_id = module.bucket_key.arn

  tags = var.tags
}

resource "aws_lambda_function" "my_lambda" {
  #checkov:skip=CKV_AWS_117:no VPC; its only dependencies are S3 and CloudWatch Logs
  #checkov:skip=CKV_AWS_272:code signing needs a signing profile, which is a release-process decision
  #checkov:skip=CKV_AWS_116:a DLQ needs SQS or SNS, and the challenge forbids a new service
  function_name = var.function_name

  s3_bucket = aws_s3_bucket.my_bucket.bucket

  # A reference, not a literal, which is also the dependency the original
  # was missing.
  s3_key = aws_s3_object.lambda_zip.key

  handler = "handler.handler"

  # FIX 6. The original was python3.8, past end of support.
  runtime = var.runtime

  role = aws_iam_role.iam_for_lambda.arn

  # FIX 5. Without this a code change uploads a new zip and leaves the
  # function running the old one, with no diff to explain it.
  source_code_hash = data.archive_file.lambda.output_base64sha256

  timeout     = var.timeout
  memory_size = var.memory_size

  # A runaway trigger would otherwise consume the account's whole pool.
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      DATA_BUCKET = aws_s3_bucket.my_bucket.bucket
    }
  }

  kms_key_arn = module.bucket_key.arn

  tracing_config {
    mode = "PassThrough"
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}
