# Modules

Ten modules, one copy of each, shared by all three tasks. Nothing here is
task-specific: what differs between a public web tier and a fully private
workload is configuration, not a second copy of the code.

## Consuming them

Root configurations reference these by git URL at a version tag, not by
relative path:

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.0.0"

  name       = "myapp-production"
  cidr_block = "10.20.0.0/16"
}
```

The `//` separates the repository from the path inside it. The `?ref=` is a
git ref: a tag, a branch or a commit SHA. Always a tag.

`terraform init` clones the repository at that tag into `.terraform/modules/`.
`terraform get -update` re-fetches when the ref moves, which for a tag it
should not.

## Versioning

One tag for the whole repository. Every module shares it.

```bash
git tag -a v1.1.0 -m "..." && git push origin v1.1.0
```

Bump the minor version for a backwards-compatible addition, the major for a
breaking change to a module's interface, the patch for a fix that changes no
inputs or outputs. [`CHANGELOG.md`](CHANGELOG.md) records what each version
changed.

### Tags must be immutable

A git tag is a mutable pointer. Anyone with write access can move `v1.0.0` to
a different commit, and every later `terraform init` then pulls different code
under the same ref, with nothing changing in any root configuration to show it.

Checkov's `CKV_TF_1` flags exactly this and would rather see a commit SHA. We
use tags anyway, because a version is something a human reads in a diff:
"v1.0.0 to v1.1.0" says what happened, where "4840a3b to 9c2f1de" says nothing,
so nobody reads it and the upgrade stops being reviewed.

That trade is only sound if the tags cannot move, which is a repository
setting rather than a Terraform one. Add a tag protection rule for `v*` under
Settings, Rules, refusing updates and deletions. The reasoning is written out
in `.checkov.yaml` next to the suppression.

For a module published by someone else, pin the SHA.

Nothing consumes a module until a tag points at it. That is the trade-off of
versioning rather than referencing the working tree, and it is worth being
explicit about it:

**A change to a module has no effect on any root configuration until you tag
and push it.** Edit `modules/vpc`, run `terraform plan` in
`task1-terraform-module`, and you will see no diff, because `init` fetched
`v1.0.0` from GitHub rather than reading the directory next door. CI has the
same property: a pull request that changes a module still validates the root
configurations against the last tag.

That is the point. A root configuration pinned to `v1.0.0` keeps working
exactly as it did the day it was pinned, whatever happens on `main`. The cost
is a release step. The usual way to make that cost feel smaller is to move the
modules into a repository of their own, with its own tags and its own CI, so
"release a module" and "change an environment" stop sharing a commit history.
They are together here because the challenge is one deliverable.

To iterate on a module without tagging, point the source at the working tree
temporarily:

```hcl
source = "../modules/vpc"   # local, for development only
```

and switch it back before committing. Relative sources *inside* `modules/` are
different and are correct permanently: Terraform resolves them within the same
fetched copy, so `modules/vpc` referencing `../security-group` gets the
security-group module at its own version rather than letting the two drift.

## The modules

| Module | What it is |
|---|---|
| [`security-group/`](security-group/) | A security group where every rule is its own resource, so changing one rule never touches another |
| [`kms-key/`](kms-key/) | A customer-managed KMS key with rotation on and a readable key policy |
| [`vpc/`](vpc/) | VPC, public and private subnets, NAT, optional flow logs, optional VPC endpoints |
| [`ec2/`](ec2/) | An instance with encrypted storage, IMDSv2 required, and no public address unless asked |
| [`rds/`](rds/) | A private, encrypted database with enhanced monitoring and a parameter group of its own |
| [`iam-instance-role/`](iam-instance-role/) | An instance role and profile, scoped to one bucket, one prefix and one key |
| [`cloudtrail/`](cloudtrail/) | Multi-region trail with log file validation, delivering to S3 and CloudWatch Logs |
| [`aws-config/`](aws-config/) | Configuration recorder, delivery channel and twenty managed rules |
| [`security-alerting/`](security-alerting/) | Metric filters and alarms on the events worth paging for |
| [`secret/`](secret/) | A generated credential in Secrets Manager |

`security-group/` and `kms-key/` have READMEs of their own, because their
design is the argument rather than the implementation. The rest document
themselves through their variable descriptions and inline comments; run
`terraform-docs` against any of them for a generated reference.

## Which modules each task uses

| Module | Task 1 | Task 2 | Task 3 |
|---|:---:|:---:|:---:|
| `security-group` | yes | yes | |
| `kms-key` | yes | yes | yes |
| `vpc` | yes | yes | |
| `ec2` | yes | yes | |
| `rds` | yes | | |
| `iam-instance-role` | | yes | |
| `cloudtrail` | | yes | |
| `aws-config` | | yes | |
| `security-alerting` | | yes | |
| `secret` | | yes | |

Two rows are worth pausing on.

`vpc` serves Task 1's internet-facing web tier and Task 2's fully private
workload from the same code. Task 1 sets `map_public_ip_on_launch = true` and
leaves flow logs and endpoints off. Task 2 leaves public addressing off and
turns on flow logs, three interface endpoints and the S3 gateway endpoint.
Before consolidation these were two modules, `vpc` and `network`, that shared
roughly eighty percent of their contents and had already started to drift.

`ec2` is the same story. Task 1's instance is public with a security group
allowing HTTPS from named networks; Task 2's is private with a security group
that has no ingress rules at all. The module does not create the security
group precisely so that both can be expressed without a flag: the caller
composes `security-group` and passes the ids in.
