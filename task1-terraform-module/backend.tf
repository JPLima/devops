terraform {
  # Partial configuration. The bucket and lock table are account-specific and
  # are created by ./bootstrap, so they come from backend.hcl at init time:
  #
  #   terraform init -backend-config=backend.hcl
  #
  # workspace_key_prefix keeps each workspace's state under its own prefix, so
  # staging and production never share a state file or a lock.
  backend "s3" {
    key                  = "task1/terraform.tfstate"
    workspace_key_prefix = "env"
    encrypt              = true
  }
}
