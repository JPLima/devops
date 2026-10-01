terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Local state: this configuration creates the remote backend.
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
