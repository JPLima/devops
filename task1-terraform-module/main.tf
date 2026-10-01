# Environments are workspaces. Everything that differs between them is in
# local.environments.

module "data_key" {
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

  alias       = "${local.name_prefix}-data"
  description = "Encrypts EBS and RDS storage for ${local.name_prefix}"

  tags = local.tags
}

module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.1.0"

  name       = local.name_prefix
  cidr_block = local.config.vpc_cidr
  az_count   = local.config.az_count

  enable_nat_gateway = true
  single_nat_gateway = local.config.single_nat_gateway

  map_public_ip_on_launch = true

  tags = local.tags
}

# One rule per allow-listed network, keyed by its name, so adding or removing
# a CIDR plans a single create or destroy.
module "web_sg" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-group?ref=v1.1.0"

  name        = "${local.name_prefix}-web"
  description = "Web tier for ${local.name_prefix}"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    for name, cidr in var.web_ingress_cidrs :
    "https-from-${name}" => {
      description = "HTTPS from ${name}"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = cidr
    }
  }

  egress_rules = {
    "https-to-internet" = {
      description = "Outbound HTTPS for package and API access"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "0.0.0.0/0"
    }

    "postgres-to-vpc" = {
      description = "Reach the database inside the VPC"
      ip_protocol = "tcp"
      from_port   = local.db_port
      to_port     = local.db_port
      cidr_ipv4   = module.vpc.vpc_cidr_block
    }
  }

  tags = local.tags
}

# References the web tier by group id rather than CIDR, so the rule survives
# instances being replaced or scaled.
module "db_sg" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-group?ref=v1.1.0"

  name        = "${local.name_prefix}-db"
  description = "Database tier for ${local.name_prefix}"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    "postgres-from-web-tier" = {
      description                  = "PostgreSQL from the web tier"
      ip_protocol                  = "tcp"
      from_port                    = local.db_port
      to_port                      = local.db_port
      referenced_security_group_id = module.web_sg.id
    }
  }

  # A database has no reason to open outbound connections.
  egress_rules = {}

  tags = local.tags
}

module "ec2" {
  source = "git::https://github.com/JPLima/devops.git//modules/ec2?ref=v1.1.0"

  name               = "${local.name_prefix}-web"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.web_sg.id]
  instance_type      = local.config.instance_type
  kms_key_arn        = module.data_key.arn

  associate_public_ip_address = true

  tags = local.tags
}

module "rds" {
  source = "git::https://github.com/JPLima/devops.git//modules/rds?ref=v1.1.0"

  name               = "${local.name_prefix}-db"
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.db_sg.id]
  port               = local.db_port

  instance_class          = local.config.db_instance_class
  allocated_storage       = local.config.db_allocated_storage
  multi_az                = local.config.db_multi_az
  backup_retention_period = local.config.backup_retention_period
  deletion_protection     = local.config.deletion_protection
  skip_final_snapshot     = local.config.skip_final_snapshot

  kms_key_arn = module.data_key.arn
  password    = var.db_password

  tags = local.tags
}
