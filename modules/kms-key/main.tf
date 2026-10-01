data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_109:account root statement is mandatory on a key policy
  #checkov:skip=CKV_AWS_111:same statement, scoped to this key
  #checkov:skip=CKV_AWS_356:a key policy's Resource is always "*", meaning this key

  # IAM policies alone cannot grant access to a KMS key, so the account root
  # has to be able to delegate. Without this the key is unmanageable.
  statement {
    sid    = "EnableIAMPolicies"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  dynamic "statement" {
    for_each = length(var.service_principals) > 0 ? [1] : []

    content {
      sid    = "AllowServiceUse"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = var.service_principals
      }

      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
      ]

      resources = ["*"]

      dynamic "condition" {
        for_each = var.service_condition != null ? [var.service_condition] : []

        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_kms_key" "this" {
  description             = var.description
  policy                  = data.aws_iam_policy_document.key.json
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_window_in_days

  tags = merge(var.tags, { Name = var.alias })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias}"
  target_key_id = aws_kms_key.this.key_id
}
