locals {
  # Per-environment settings, indexed by workspace name. This is the bonus
  # requirement: one configuration, several environments, no duplicated root
  # modules to drift apart.
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

  # No default on this lookup on purpose. A typo in the workspace name, or the
  # default workspace, fails immediately instead of quietly deploying
  # production sizing into a scratch workspace, or the reverse.
  #
  # The consequence is that terraform validate needs a workspace too:
  #   TF_WORKSPACE=staging terraform validate
  # which is what CI does. TF_WORKSPACE works without an initialised backend.
  config = local.environments[terraform.workspace]

  name_prefix = "${var.project}-${terraform.workspace}"

  # Resource-level tags. Provider default_tags covers the common ones; these
  # are the ones the security-group module applies to individual rules.
  tags = {
    Project     = var.project
    Environment = terraform.workspace
  }

  db_port = 5432
}
