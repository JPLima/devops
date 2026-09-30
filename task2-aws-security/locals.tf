data "aws_caller_identity" "current" {}

locals {
  name_prefix = var.project

  # S3 bucket names are a single global namespace. Suffixing with the account
  # id makes them unique without a random resource, so the name stays stable
  # across a state rebuild.
  bucket_suffix = data.aws_caller_identity.current.account_id

  tags = {
    Project = var.project
  }
}
