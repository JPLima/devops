# security-group

A security group where every rule is its own Terraform resource, so changing
one rule never touches another.

Shared by `task1-terraform-module` and `task2-aws-security`.

## The problem this solves

Three ways to express security group rules, and what each does when you remove
one CIDR from a set of four:

| Pattern | Plan when removing one CIDR |
|---|---|
| Inline `ingress` blocks on `aws_security_group` | The whole `ingress` attribute is rewritten. The provider revokes and re-authorises rules that did not change. |
| `aws_security_group_rule` with `count` over a list | Removing index 1 shifts indices 2 and 3 down. Three rules are destroyed and two recreated to remove one. |
| `aws_vpc_security_group_ingress_rule` with `for_each` over a map | One destroy. Nothing else appears in the plan. |

This module is the third. The `aws_security_group` resource carries no inline
rules at all, because inline blocks and standalone rule resources overwrite
each other on every apply.

## Usage

```hcl
module "web_sg" {
  source = "../../modules/security-group"

  name        = "web"
  description = "Public web tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    "https-from-office-lisbon" = {
      description = "HTTPS from the Lisbon office"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "203.0.113.10/32"
    }

    "https-from-office-porto" = {
      description = "HTTPS from the Porto office"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = "198.51.100.7/32"
    }
  }

  egress_rules = {
    "all-outbound" = {
      description = "Unrestricted egress"
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  tags = local.tags
}
```

Delete the `https-from-office-porto` entry and the plan is:

```
# module.web_sg.aws_vpc_security_group_ingress_rule.this["https-from-office-porto"] will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.
```

The security group and the Lisbon rule do not appear, because they did not
change. The map key is the resource address, and keys do not move when their
neighbours change.

### Verified, not asserted

Two real plans against an AWS account, differing only in the allow-list, with
the resource addresses extracted from each:

```bash
terraform plan -out=a.plan \
  -var 'web_ingress_cidrs={"office-lisbon"="203.0.113.10/32","vpn-gateway"="203.0.113.64/26"}'

terraform plan -out=b.plan \
  -var 'web_ingress_cidrs={"office-lisbon"="203.0.113.10/32","vpn-gateway"="203.0.113.64/26","office-porto"="198.51.100.7/32"}'

# extract every aws_vpc_security_group_ingress_rule address from each plan
terraform show -json a.plan | jq -r '.resource_changes[]
  | select(.type|contains("security_group_ingress_rule")) | .address' | sort > a.txt
terraform show -json b.plan | jq -r '.resource_changes[]
  | select(.type|contains("security_group_ingress_rule")) | .address' | sort > b.txt

diff a.txt b.txt
```

Result:

```
2a3
> module.web_sg.aws_vpc_security_group_ingress_rule.this["https-from-office-porto"]
```

One line added. Nothing changed, nothing removed. Every address that already
existed is byte-for-byte identical.

That last sentence is the whole point, and it is what `count` over a list
cannot give you: there, inserting or removing an entry renumbers every index
after it, so the addresses themselves move and Terraform destroys and recreates
rules that nobody touched.

## Referencing another security group

Prefer `referenced_security_group_id` over a CIDR when the source is something
you also manage. The rule then stays correct when instance addresses change:

```hcl
ingress_rules = {
  "postgres-from-web-tier" = {
    description                  = "PostgreSQL from the web tier"
    ip_protocol                  = "tcp"
    from_port                    = 5432
    to_port                      = 5432
    referenced_security_group_id = module.web_sg.id
  }
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Base name, used as a `name_prefix`. |
| `description` | `string` | required | AWS does not allow this to change after creation. |
| `vpc_id` | `string` | required | VPC the group belongs to. |
| `ingress_rules` | `map(object)` | `{}` | Inbound rules, keyed by name. |
| `egress_rules` | `map(object)` | `{}` | Outbound rules, keyed by name. |
| `tags` | `map(string)` | `{}` | Applied to the group and to every rule. |

Each rule object takes `description`, `ip_protocol`, optional `from_port` and
`to_port`, and exactly one of `cidr_ipv4`, `cidr_ipv6`, `prefix_list_id` or
`referenced_security_group_id`.

Two variable validations catch the common mistakes at plan time rather than as
an API error mid-apply: setting zero or more than one source, and omitting
ports on a rule whose protocol is not `-1`.

## Outputs

| Name | Description |
|---|---|
| `id` | Group id, for use as `referenced_security_group_id` elsewhere. |
| `arn` | Group ARN. |
| `name` | Generated name, including the prefix suffix. |
| `ingress_rule_ids` | Map of rule key to AWS rule id. |
| `egress_rule_ids` | Map of rule key to AWS rule id. |

## Notes

Rule keys are part of the resource address. Renaming a key destroys the old
rule and creates a new one, which is correct but worth knowing. Use
`terraform state mv` if you want to rename without the churn.

The group uses `name_prefix` with `create_before_destroy`, so a change that
forces replacement creates the new group before detaching the old one.

AWS attaches an allow-all egress rule to every new security group. This module
does not manage that rule, so declare the egress you want in `egress_rules`
and handle the default according to your account's baseline.
