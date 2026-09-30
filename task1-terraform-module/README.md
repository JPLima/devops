# Task 1: Terraform module

A VPC with an EC2 instance and an RDS instance, built from modules, with remote
state in S3 and locking in DynamoDB. Environments are Terraform workspaces.

## Prerequisites

- Terraform >= 1.9
- AWS credentials with permission to create VPC, EC2, RDS, S3, DynamoDB and KMS
  resources. Use a role, not a long-lived access key.
- A region. Everything defaults to `eu-west-1`.

## Layout

```
task1-terraform-module/
├── bootstrap/              creates the state bucket and lock table (local state)
├── backend.tf              partial S3 backend configuration
├── locals.tf               per-workspace settings
├── main.tf                 wires the modules together
├── variables.tf
├── outputs.tf
└── {staging,production}.tfvars
```

There is no `modules/` directory here. Every module lives once at the
repository root and is consumed by git URL at a version tag:

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.0.0"
  ...
}
```

This task uses `vpc`, `ec2`, `rds`, `security-group` and `kms-key`. The `vpc`
and `ec2` modules are the same ones Task 2 uses; what makes this a public web
tier rather than a private workload is `map_public_ip_on_launch = true` and
`associate_public_ip_address = true`, not different code. See
[`../modules/README.md`](../modules/README.md).

## Running it

### 1. Bootstrap the backend, once per account

The backend cannot create the bucket it stores state in, so this runs first,
with local state.

```bash
cd bootstrap
terraform init
terraform apply -var="state_bucket_name=betontalent-terraform-state-<unique>"
```

It prints a ready-to-paste `backend_block` output. The bucket is versioned,
encrypted with a customer-managed KMS key, blocked from public access, and
refuses non-TLS requests. Both it and the lock table carry `prevent_destroy`.

### 2. Point the root module at it

```bash
cd ..
cp backend.hcl.example backend.hcl   # fill in the bucket name from step 1
terraform init -backend-config=backend.hcl
```

`backend.hcl` is gitignored because the bucket name is account-specific.

### 3. Create the workspaces

```bash
terraform workspace new staging
terraform workspace new production
```

### 4. Apply

```bash
export TF_VAR_db_password="$(openssl rand -base64 24)"

terraform workspace select staging
terraform plan  -var-file=staging.tfvars
terraform apply -var-file=staging.tfvars
```

Production is the same with `production.tfvars`.

## Environments

`local.environments` in `locals.tf` maps a workspace name to everything that
differs between environments:

| Setting | staging | production |
|---|---|---|
| VPC CIDR | `10.10.0.0/16` | `10.20.0.0/16` |
| Availability zones | 2 | 3 |
| NAT gateways | 1, shared | one per AZ |
| EC2 instance type | `t3.micro` | `t3.small` |
| RDS instance class | `db.t4g.micro` | `db.t4g.small` |
| RDS multi-AZ | no | yes |
| Backup retention | 1 day | 30 days |
| Deletion protection | off | on |
| Final snapshot on destroy | skipped | taken |

`local.config = local.environments[terraform.workspace]` has no default. An
unknown workspace fails at plan time rather than deploying the wrong sizing.
That includes the `default` workspace, which is deliberate: there is no such
environment.

Because of that, `terraform validate` needs a workspace as well:

```bash
TF_WORKSPACE=staging terraform validate
```

`TF_WORKSPACE` works without an initialised backend, which is what makes this
usable in CI.

## Security groups

The web tier's rules are generated from `var.web_ingress_cidrs`, a map keyed by
network name:

```hcl
web_ingress_cidrs = {
  "office-lisbon" = "203.0.113.10/32"
  "vpn-gateway"   = "203.0.113.64/26"
}
```

Each entry becomes its own `aws_vpc_security_group_ingress_rule`, addressed by
its key. Adding `"office-porto"` produces a plan with one create. Removing
`"vpn-gateway"` produces a plan with one destroy. The security group and the
other rules do not appear, because they did not change.

A variable validation rejects `0.0.0.0/0`: an allow-list that allows everything
is not an allow-list.

The database group has exactly one ingress rule, and it references the web tier
group by id rather than by CIDR. Instances can be replaced or scaled and the
rule stays correct. It has no egress rules at all.

## Design choices

**Workspaces rather than directories per environment.** The challenge names
workspaces as the bonus. The trade-off is real: workspaces share one backend
and one set of credentials, so they suit environments in the same account.
Separate accounts per environment would want separate configurations, and
`locals.tf` is where that decision would be revisited.

**Subnet CIDRs are computed, not listed.** `cidrsubnet` derives them from the
VPC CIDR. Changing the VPC size or adding an AZ does not require the caller to
recalculate anything, and public subnets take the low half of the plan so
adding a zone never renumbers an existing subnet.

**Subnets are keyed by availability zone, not by index.** Removing a zone
destroys one subnet instead of shifting every index after it.

**The AMI is a data source with `ignore_changes = [ami]`.** Hardcoding an AMI
id pins the configuration to one region and one patch level. Resolving it at
plan time without `ignore_changes` would replace a running instance whenever
Amazon publishes a new image. Replacing is a deliberate act.

**RDS gets its own parameter group even with almost no overrides.** The default
group cannot be modified, so without this the first parameter anyone needs to
change forces a replacement of the instance.

**`final_snapshot_identifier` uses `timestamp()` under `ignore_changes`.** The
function is evaluated on every plan, so without `ignore_changes` the instance
would show a diff on every run. The value only matters at destroy time.

**The RDS password is a sensitive variable, not a Secrets Manager secret.**
Task 1 does not ask for Secrets Manager and Task 2 does, so the contrast is
visible between the two. It is redacted from plan output but it is still in
state, which is why the state bucket is encrypted with a customer-managed key.

**Tags are set once in `default_tags` on the provider.** Repeating them per
resource is how tagging drifts.

## Idempotency

A second `terraform apply` with no changes plans nothing. The things that
usually break that are handled explicitly: no bare `timestamp()`, the AMI
lookup is pinned by `ignore_changes`, the RDS final snapshot name is ignored,
and there are no `random` resources without stable inputs.

## Outputs

`vpc_id`, `public_subnet_ids`, `private_subnet_ids`, `ec2_public_ip`,
`ec2_public_dns`, `ec2_private_dns`, `rds_endpoint`, `rds_address`, `rds_port`,
`web_security_group_id`, `web_ingress_rule_ids`, `db_security_group_id`,
`environment`.

`rds_endpoint` is not marked sensitive: it is a hostname on a private subnet,
and marking hostnames sensitive trains people to ignore the marker. The
password never appears in an output.
