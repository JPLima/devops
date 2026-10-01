locals {
  environments = {
    staging = {
      vpc_cidr                = "10.10.0.0/16"
      az_count                = 2
      single_nat_gateway      = true
      instance_type           = "t3.micro"
      db_instance_class       = "db.t4g.micro"
      db_allocated_storage    = 20
      db_multi_az             = false
      backup_retention_period = 1
      deletion_protection     = false
      skip_final_snapshot     = true
    }

    production = {
      vpc_cidr                = "10.20.0.0/16"
      az_count                = 3
      single_nat_gateway      = false
      instance_type           = "t3.small"
      db_instance_class       = "db.t4g.small"
      db_allocated_storage    = 100
      db_multi_az             = true
      backup_retention_period = 30
      deletion_protection     = true
      skip_final_snapshot     = false
    }
  }

  # No default: an unknown workspace fails rather than deploying the wrong
  # sizing. So validate needs TF_WORKSPACE=staging, which is what CI sets.
  config = local.environments[terraform.workspace]

  name_prefix = "${var.project}-${terraform.workspace}"

  tags = {
    Project     = var.project
    Environment = terraform.workspace
  }

  db_port = 5432
}
