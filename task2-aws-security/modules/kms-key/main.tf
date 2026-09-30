# A customer-managed KMS key.
#
# AWS-managed keys cannot have their policy inspected or their rotation
# schedule changed, and they cannot be shared across accounts. Anything worth
# auditing gets a key of its own.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "key" {
  #checkov:skip=CKV_AWS_109:The account root statement is required. IAM policies alone cannot grant access to a KMS key, so without it the key becomes unmanageable and AWS support is the only way back.
  #checkov:skip=CKV_AWS_111:Same statement. It is scoped to this key, which is the only resource a key policy can name.
  #checkov:skip=CKV_AWS_356:A key policy's Resource is always "*", meaning this key. There is no narrower form.

  # Without this, the key becomes unmanageable: IAM policies alone cannot grant
  # access to a KMS key, so the account root has to be able to delegate.
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

      # No kms:Delete or kms:ScheduleKeyDeletion. A service needs to encrypt
      # and decrypt, never to destroy the key.
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
