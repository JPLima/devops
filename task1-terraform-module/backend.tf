# Partial configuration. The bucket and lock table come from ./bootstrap, so
# they are supplied at init time: terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key                  = "task1/terraform.tfstate"
    workspace_key_prefix = "env"
    encrypt              = true
  }
}
