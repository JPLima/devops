# A PostgreSQL instance in private subnets, encrypted, and unreachable from
# the internet.

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })
}

# A parameter group of our own, even with no overrides yet. The default group
# cannot be modified, so without this the first setting anyone needs to change
# forces a replacement of the instance.
resource "aws_db_parameter_group" "this" {
  name_prefix = "${var.name}-"
  family      = "${var.engine}${split(".", var.engine_version)[0]}"

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    create_before_destroy = true
  }
}

# Enhanced monitoring publishes to CloudWatch Logs under an AWS-owned account,
# so it needs a role of its own rather than the instance's.
data "aws_iam_policy_document" "monitoring_assume" {
  count = var.monitoring_interval > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${var.name}-monitoring-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume[0].json

  tags = merge(var.tags, { Name = "${var.name}-monitoring" })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_db_instance" "this" {
  identifier = var.name

  engine         = var.engine
  engine_version = var.engine_version
  instance_class = var.instance_class

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"

  storage_encrypted = true
  kms_key_id        = var.kms_key_arn

  db_name  = var.database_name
  username = var.username
  password = var.password
  port     = var.port

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  # The subnet group is private, but this is the switch that actually decides
  # whether AWS hands out a public endpoint.
  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"

  # Patch in the maintenance window rather than the moment AWS publishes.
  auto_minor_version_upgrade = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  copy_tags_to_snapshot           = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = var.kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # timestamp() in final_snapshot_identifier is evaluated on every plan.
    # Without this the instance would show a diff on every run, which is the
    # opposite of idempotent. The value only matters at destroy time.
    ignore_changes = [final_snapshot_identifier]
  }
}
