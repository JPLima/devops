# rds

A PostgreSQL instance in private subnets: encrypted, unreachable from the
internet, with enhanced monitoring and a parameter group of its own.

## Usage

```hcl
module "database" {
  source = "git::https://github.com/JPLima/devops.git//modules/rds?ref=v1.1.0"

  name               = "myapp-production-db"
  subnet_ids         = module.vpc.private_subnet_ids
  security_group_ids = [module.db_sg.id]

  instance_class    = "db.t4g.small"
  allocated_storage = 100
  kms_key_arn       = module.data_key.arn

  password = var.db_password   # sensitive, supplied out of band

  tags = { Project = "myapp" }
}
```

Supply the password through the environment, never a committed tfvars file:

```bash
export TF_VAR_db_password="$(openssl rand -base64 24)"
```

### A throwaway environment

```hcl
multi_az                = false   # defaults to true
backup_retention_period = 1
deletion_protection     = false
skip_final_snapshot     = true
```

### The security group that goes with it

Reference the application tier by id rather than by CIDR, so the rule stays
correct when instance addresses change:

```hcl
module "db_sg" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-group?ref=v1.1.0"

  name        = "myapp-db"
  description = "Database tier"
  vpc_id      = module.vpc.vpc_id

  ingress_rules = {
    "postgres-from-app-tier" = {
      description                  = "PostgreSQL from the application tier"
      ip_protocol                  = "tcp"
      from_port                    = 5432
      to_port                      = 5432
      referenced_security_group_id = module.app_sg.id
    }
  }

  # A database has no reason to open outbound connections.
  egress_rules = {}
}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Identifier prefix for the instance and its subnet group. |
| `subnet_ids` | `list(string)` | required | Private subnets. At least two, in different AZs. |
| `security_group_ids` | `list(string)` | required | Groups controlling access. |
| `password` | `string` | required | Master password. Sensitive. |
| `engine` | `string` | `"postgres"` | Database engine. |
| `engine_version` | `string` | `"16.4"` | Engine version. Pinned, so an upgrade is a deliberate commit. |
| `instance_class` | `string` | `"db.t4g.micro"` | Instance class. |
| `allocated_storage` | `number` | `20` | Allocated storage in GiB. |
| `max_allocated_storage` | `number` | `100` | Upper bound for storage autoscaling. |
| `database_name` | `string` | `"appdb"` | Database created on the instance. |
| `username` | `string` | `"dbadmin"` | Master username. |
| `port` | `number` | `5432` | Port the engine listens on. |
| `multi_az` | `bool` | `true` | Synchronous standby in a second AZ. |
| `backup_retention_period` | `number` | `7` | Days of automated backups. Zero disables them. |
| `deletion_protection` | `bool` | `true` | Refuse to delete the instance through the API. |
| `skip_final_snapshot` | `bool` | `false` | Skip the final snapshot on destroy. |
| `kms_key_arn` | `string` | `null` | Key for storage, Performance Insights and exported logs. |
| `monitoring_interval` | `number` | `60` | Enhanced monitoring sample interval. Zero disables it. |
| `performance_insights_retention_period` | `number` | `7` | Days of Performance Insights history. 7 is the free tier. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `endpoint` | Connection endpoint, host and port. |
| `address` | Hostname of the instance. |
| `port` | Port the instance listens on. |
| `database_name` | Database created on the instance. |
| `identifier` | RDS instance identifier. |
| `arn` | Instance ARN. |

## Notes

**`multi_az` defaults to `true`.** High availability should be something you opt
out of for a throwaway environment, not something you remember to opt into for
a production one. It roughly doubles the instance cost. This changed in
[v1.1.0](../CHANGELOG.md); callers that did not set it will see a standby
appear in the next plan.

**A parameter group is created even with almost no overrides.** The default
group cannot be modified, so without this the first parameter anyone needs to
change forces a replacement of the instance.

**`final_snapshot_identifier` uses `timestamp()` under `ignore_changes`.** The
function is evaluated on every plan, so without the ignore the instance would
show a diff on every run. The value only matters at destroy time.

**`publicly_accessible` is hardcoded to `false`.** The subnet group being
private is not what decides this; this attribute is. It is not exposed as a
variable, because a database reachable from the internet is not a
configuration, it is an incident.

**The password ends up in state.** `sensitive` redacts it from plan output, but
state holds it in clear. Encrypt the state bucket with a customer-managed key,
and prefer the `secret` module plus a rotation lambda where the value matters.

**Enhanced monitoring creates its own IAM role.** It publishes to CloudWatch
Logs under an AWS-owned account, so it cannot use the instance's role. Set
`monitoring_interval = 0` to skip both.
