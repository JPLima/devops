# The instance role, written as least privilege rather than assembled from
# managed policies.
#
# The one managed policy here is AmazonSSMManagedInstanceCore, which is the
# documented contract for Session Manager. Rewriting it by hand would drift
# from AWS as the agent changes, which is the case where a managed policy is
# the right answer.

data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.assume.json

  # One hour rather than the twelve-hour maximum. Instance credentials are
  # rotated by the metadata service anyway; a shorter ceiling limits how long
  # a leaked set stays usable.
  max_session_duration = 3600

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "workload" {
  # Object access, scoped to one prefix of one bucket.
  statement {
    sid    = "ReadWriteOwnObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]

    resources = ["${var.data_bucket_arn}/${var.data_bucket_prefix}"]
  }

  # ListBucket is a bucket-level action, so it needs the bucket ARN without a
  # key suffix. The condition keeps the listing to the same prefix.
  statement {
    sid    = "ListOwnPrefix"
    effect = "Allow"

    actions   = ["s3:ListBucket"]
    resources = [var.data_bucket_arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = [var.data_bucket_prefix]
    }
  }

  # Without these, every GetObject and PutObject against the encrypted bucket
  # returns AccessDenied, and the error names S3 rather than KMS, which is a
  # reliable afternoon lost.
  statement {
    sid    = "UseBucketKey"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]

    resources = [var.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${data.aws_region.current.region}.amazonaws.com"]
    }
  }

  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadOwnSecrets"
      effect    = "Allow"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = var.secret_arns
    }
  }
}

data "aws_region" "current" {}

resource "aws_iam_policy" "workload" {
  name_prefix = "${var.name}-"
  description = "Least privilege workload access for ${var.name}"
  policy      = data.aws_iam_policy_document.workload.json

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_iam_role_policy_attachment" "workload" {
  role       = aws_iam_role.instance.name
  policy_arn = aws_iam_policy.workload.arn
}

resource "aws_iam_instance_profile" "instance" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.instance.name

  tags = merge(var.tags, { Name = var.name })
}
