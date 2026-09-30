# UNCHANGED from the original. The challenge forbids changing provider
# settings, so the region stays us-east-1 even though it is not where the rest
# of this repository deploys.
provider "aws" {
  region = "us-east-1"
}

# Used to build the kms:ViaService condition on the Lambda's policy and the
# encryption context condition on the key policy.
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Data bucket
# ---------------------------------------------------------------------------

# FIX 1. The original hardcoded bucket = "my-super-cool-bucket". S3 names are
# globally unique across every AWS account, so apply failed with
# BucketAlreadyExists for anyone who was not first.
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "${var.bucket_prefix}-${random_id.bucket_suffix.hex}"

  # FIX 2. The original set acl = "private" here. That argument was deprecated
  # in AWS provider v4 and removed from this resource in v5, so with any
  # current provider the configuration does not even validate.
  #
  # It is not replaced with an aws_s3_bucket_acl resource, because ACLs are the
  # wrong tool: BucketOwnerEnforced below disables them entirely, which is
  # stricter than a private ACL and cannot be undone by a careless PutObjectAcl.

  # Object-level cleanup happens through the lifecycle rule below, so the
  # bucket can be destroyed without a manual empty step.
  force_destroy = true

  tags = merge(var.tags, { Name = "${var.function_name}-data" })
}

resource "aws_s3_bucket_ownership_controls" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# FIX 8a. The original bucket had no versioning, no encryption and no public
# access block. The challenge asks for encryption on storage services and for
# the bucket to be correctly configured.
resource "aws_s3_bucket_versioning" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

# The same kms-key module Tasks 1 and 2 use. KMS was already in play here
# through the bucket's encryption, so this introduces no new AWS service; it
# replaces the AWS-managed key with one whose policy and rotation are ours.
module "bucket_key" {
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.0.0"

  alias                   = "${var.function_name}-data"
  description             = "Encrypts objects written by ${var.function_name}, its log group and its environment variables"
  deletion_window_in_days = 7

  # CloudWatch Logs encrypts on its own behalf and cannot assume a role, so it
  # needs a grant in the key policy itself. S3 and Lambda authorise through the
  # caller's identity and are covered by the account root statement.
  service_principals = ["logs.${data.aws_region.current.region}.amazonaws.com"]

  # Narrowed to log groups in this account, so the grant cannot be used to
  # decrypt anything else that happens to reach CloudWatch Logs.
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

  # Separate rule with no prefix filter. An interrupted upload leaves parts
  # that are billed but never appear in a listing, and the deployment zip is
  # not under invocations/, so a prefix-scoped rule would miss exactly the
  # object most likely to be re-uploaded.
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

# ---------------------------------------------------------------------------
# Deployment package
# ---------------------------------------------------------------------------

# FIX 3. The original set s3_key = "lambda_function_payload.zip" on the
# function, but nothing ever created that object. Apply failed on a key that
# was not there.
#
# archive_file builds the zip during plan, from source, so there is no manual
# step and no binary committed to the repository.
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/.build/lambda_function_payload.zip"

  # Without a fixed mtime, the zip's checksum changes on every run and the
  # function redeploys on every apply. This is the difference between an
  # idempotent configuration and one that always has a diff.
  output_file_mode = "0644"
}

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.my_bucket.id
  key    = "lambda_function_payload.zip"
  source = data.archive_file.lambda.output_path

  # Tells S3 to replace the object when the zip changes. Without it, a code
  # change uploads nothing.
  etag = data.archive_file.lambda.output_md5

  # The bucket default would apply anyway; being explicit means a future change
  # to the bucket default cannot silently leave this object unencrypted.
  server_side_encryption = "aws:kms"
  kms_key_id             = module.bucket_key.arn

  tags = var.tags

  depends_on = [aws_s3_bucket_server_side_encryption_configuration.my_bucket]
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

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

# FIX 4. The original role had a trust policy and no permissions policy at all.
# The function could not write logs, so every failure was invisible: the
# invocation errored and CloudWatch had nothing to show for it.
#
# Not AWSLambdaBasicExecutionRole, which grants logs:CreateLogGroup on "*" and
# lets the function write into any log group in the account. This is scoped to
# the one group the function owns.
#
# FIX 8b. The S3 and KMS statements are what make the success criterion
# testable: the handler writes an object and reads it back, which it cannot do
# without both.
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

    # One prefix of one bucket, not the whole bucket and not s3:*.
    resources = ["${aws_s3_bucket.my_bucket.arn}/invocations/*"]
  }

  # Without these, every PutObject and GetObject against the encrypted bucket
  # returns AccessDenied, and the error names S3 rather than KMS.
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

# ---------------------------------------------------------------------------
# Function
# ---------------------------------------------------------------------------

# Created explicitly rather than left to Lambda. A log group Lambda creates on
# first invocation has no retention and no tags, so logs accumulate forever and
# nothing can be scoped to it in an IAM policy, because it does not exist yet.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  # Log lines routinely carry more than anyone intends. Encrypting the group
  # with the same customer-managed key as the bucket keeps one audit story.
  kms_key_id = module.bucket_key.arn

  tags = var.tags
}

resource "aws_lambda_function" "my_lambda" {
  #checkov:skip=CKV_AWS_117:No VPC. The function's only dependencies are S3 and CloudWatch Logs, both public endpoints. Attaching it to a VPC would add ENI cold-start latency and a NAT gateway, for no isolation gain.
  #checkov:skip=CKV_AWS_272:Code signing needs a signing profile and a publisher, which is a release-process decision rather than something this challenge's single-file function can demonstrate honestly.
  #checkov:skip=CKV_AWS_116:A dead letter queue requires SQS or SNS. The challenge forbids introducing a new AWS service, and this function is invoked synchronously, where a DLQ does not apply: the caller receives the error. It would be the right addition the moment an async trigger is added.
  function_name = var.function_name

  s3_bucket = aws_s3_bucket.my_bucket.bucket

  # References the object rather than repeating the literal key. This is also
  # what creates the dependency the original was missing: Terraform now knows
  # the object must exist before the function is created.
  s3_key = aws_s3_object.lambda_zip.key

  handler = "handler.handler"

  # FIX 6. python3.8 reached end of support in October 2024 and AWS rejects
  # new functions on it.
  runtime = var.runtime

  role = aws_iam_role.iam_for_lambda.arn

  # FIX 5. The original had no source_code_hash. Changing handler.py would
  # upload a new zip to S3 and leave the deployed function running the old
  # code, with no diff in the plan to explain why.
  source_code_hash = data.archive_file.lambda.output_base64sha256

  timeout     = var.timeout
  memory_size = var.memory_size

  # Caps the blast radius. Without a reserved limit, a runaway trigger consumes
  # the account's whole concurrency pool and starves every other function.
  reserved_concurrent_executions = var.reserved_concurrent_executions

  environment {
    variables = {
      DATA_BUCKET = aws_s3_bucket.my_bucket.bucket
    }
  }

  # Lambda encrypts environment variables at rest with an AWS-managed key by
  # default. Naming our own key means the encryption is auditable.
  kms_key_arn = module.bucket_key.arn

  tracing_config {
    mode = "PassThrough"
  }

  tags = var.tags

  # Without this the function can be created before the log group exists, and
  # Lambda then creates an unmanaged group with no retention that the next
  # apply collides with.
  depends_on = [
    aws_iam_role_policy.lambda,
    aws_cloudwatch_log_group.lambda,
  ]
}
