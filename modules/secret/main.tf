resource "random_password" "this" {
  length  = var.password_length
  special = true

  # Characters that survive a shell, a connection string and YAML unquoted.
  override_special = "!#$%*()-_=+[]{}<>:?"
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
    # A rotation lambda writes new versions; without this every apply would
    # put the original value back.
    ignore_changes = [secret_string]
  }
}
