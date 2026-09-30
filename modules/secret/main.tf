# A generated credential in Secrets Manager.
#
# The contrast with Task 1 is deliberate. There, the database password is a
# sensitive input variable: redacted in plan output, but still present in state
# and still something a human has to handle. Here nobody ever sees it. It is
# generated in-process, written straight to Secrets Manager, and read at
# runtime by the instance role.
#
# The honest caveat: random_password keeps its result in Terraform state too.
# Secrets Manager wins on rotation, access control and audit, not on keeping
# the value out of state entirely. Only a rotation lambda that replaces the
# initial value achieves that.

resource "random_password" "this" {
  length  = var.password_length
  special = true

  # Characters that survive a shell, a connection string and a YAML file
  # without quoting arguments about them.
  override_special = "!#$%*()-_=+[]{}<>:?"

  # No keepers: the password must not change on its own. Rotation is an
  # explicit act, not a side effect of an unrelated apply.
}

resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description
  kms_key_id  = var.kms_key_arn

  recovery_window_in_days = var.recovery_window_in_days

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id = aws_secretsmanager_secret.this.id

  secret_string = jsonencode({
    username = var.username
    password = random_password.this.result
  })

  lifecycle {
    # Once a rotation lambda takes over, it writes new versions. Without this,
    # every apply would overwrite the rotated value with the original.
    ignore_changes = [secret_string]
  }
}
