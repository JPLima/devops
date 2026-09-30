# Applied with: terraform workspace select staging && terraform apply -var-file=staging.tfvars
#
# Sizing lives in local.environments, not here. This file carries only what is
# genuinely per-deployment rather than per-environment.

project = "betontalent"
region  = "eu-west-1"

web_ingress_cidrs = {
  "office-lisbon" = "203.0.113.10/32"
  "vpn-gateway"   = "203.0.113.64/26"
}
