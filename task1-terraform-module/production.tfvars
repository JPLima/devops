# Applied with: terraform workspace select production && terraform apply -var-file=production.tfvars

project = "betontalent"
region  = "eu-west-1"

web_ingress_cidrs = {
  "office-lisbon" = "203.0.113.10/32"
  "office-porto"  = "198.51.100.7/32"
  "vpn-gateway"   = "203.0.113.64/26"
}
