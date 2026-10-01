resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.subnet_ids

  tags = merge(var.tags, { Name = "${var.name}-subnet-group" })
}

# The default group cannot be modified, so without one of our own the first
# parameter anyone needs to change forces a replacement.
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

# Enhanced monitoring publishes under an AWS-owned account, so it needs its
# own role.
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

  publicly_accessible = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_period
  backup_window           = "02:00-03:00"
  maintenance_window      = "sun:03:30-sun:04:30"

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
    # timestamp() is evaluated on every plan, so without this the instance
    # shows a diff on every run. The value only matters at destroy time.
    ignore_changes = [final_snapshot_identifier]
  }
}
