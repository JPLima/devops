terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state on purpose. This configuration creates the remote backend, so
  # it cannot use it. Commit the resulting terraform.tfstate or keep it with
  # the person who bootstrapped the account; it holds no secrets.
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Component = "terraform-backend"
      ManagedBy = "terraform"
    }
  }
}
