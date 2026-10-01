# FIX 7. Added: the original pinned nothing, so init resolved provider v6 and
# the inline acl argument no longer existed. The provider block itself is
# untouched. See FIXES.md.

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
