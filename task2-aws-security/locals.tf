data "aws_caller_identity" "current" {}

locals {
  name_prefix = var.project

  # Unique without a random resource, so the name survives a state rebuild.
  bucket_suffix = data.aws_caller_identity.current.account_id

  tags = {
    Project = var.project
  }
}
