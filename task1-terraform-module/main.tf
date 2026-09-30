# Task 1 root module.
#
# One configuration, several environments, selected with terraform workspaces:
#
#   terraform workspace select staging && terraform apply
#   terraform workspace select production && terraform apply
#
# Everything that differs between environments lives in local.environments.

module "vpc" {
  source = "./modules/vpc"

  name               = local.name_prefix
  cidr_block         = local.config.vpc_cidr
  az_count           = local.config.az_count
  enable_nat_gateway = true
  single_nat_gateway = local.config.single_nat_gateway

  tags = local.tags
}

# Web tier security group.
#
# ingress_rules is built from var.web_ingress_cidrs with a for expression, so
# the map key of each rule is the name of the network it lets in. Add an entry
# to the variable and the plan contains one create:
#
#   module.web_sg.aws_vpc_security_group_ingress_rule.this["https-from-office-porto"]
#
# The security group and the other rules are untouched.
module "web_sg" {
  source = "../modules/security-group"

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

# Database security group.
#
# The single ingress rule references the web tier group by id rather than by
# CIDR. Instances can be replaced, scaled or renumbered and the rule stays
# correct without anyone editing it.
module "db_sg" {
  source = "../modules/security-group"

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

  # No egress. A database has no reason to open outbound connections, and
  # leaving this empty is the point of declaring egress explicitly.
  egress_rules = {}

  tags = local.tags
}

module "ec2" {
  source = "./modules/ec2"

  name               = "${local.name_prefix}-web"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.web_sg.id]
  instance_type      = local.config.instance_type

  tags = local.tags
}

module "rds" {
  source = "./modules/rds"

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

  password = var.db_password

  tags = local.tags
}
