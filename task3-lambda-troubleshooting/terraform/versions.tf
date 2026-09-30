# ADDED. The original had no required_providers block at all.
#
# This is why the original could not even be planned: with nothing pinned,
# Terraform resolves the newest AWS provider, and the inline `acl` argument on
# aws_s3_bucket was removed in provider v5. The configuration was written
# against v3 or v4 and silently rotted.
#
# The challenge forbids changing the provider settings. Those are the settings
# in the provider block itself, which is untouched below in main.tf: same
# provider, same region, same everything. This adds version constraints that
# were missing, which is the difference between reproducing a build and hoping.

terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
