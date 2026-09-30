# DevOps Code Challenge

Three tasks, one repository. Terraform throughout.

The brief is transcribed in [`docs/CHALLENGE.md`](docs/CHALLENGE.md), so the
requirements and the work sit side by side. A Portuguese translation is in
[`docs/CHALLENGE.pt.md`](docs/CHALLENGE.pt.md).

| Task | What it is | Where |
|---|---|---|
| 1 | VPC, EC2 and RDS from modules, remote state in S3 with DynamoDB locking, environments as workspaces | [`task1-terraform-module/`](task1-terraform-module/) |
| 2 | A private workload with least-privilege IAM, encryption everywhere, CloudTrail, AWS Config and alarms | [`task2-aws-security/`](task2-aws-security/) |
| 3 | A broken Lambda and Terraform project, diagnosed and fixed | [`task3-lambda-troubleshooting/`](task3-lambda-troubleshooting/) |

## Modules

Every module lives once, in [`modules/`](modules/), and the tasks consume them
by git URL at a version tag:

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.0.0"
  ...
}
```

No task has a `modules/` directory of its own. `vpc` serves Task 1's public
web tier and Task 2's private workload from the same code; so does `ec2`. See
[`modules/README.md`](modules/README.md) for the full list, the versioning
scheme, and the one real drawback of pinning to tags.

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

## Layout

```
devops/
├── modules/                every module, once
│   ├── security-group/     one resource per rule
│   ├── kms-key/            customer-managed key, rotation on
│   ├── vpc/                subnets, NAT, optional flow logs and endpoints
│   ├── ec2/                encrypted storage, IMDSv2, private by default
│   ├── rds/                private, encrypted, enhanced monitoring
│   ├── iam-instance-role/  scoped to one bucket, one prefix, one key
│   ├── cloudtrail/         multi-region, validated, to S3 and CloudWatch
│   ├── aws-config/         recorder, delivery channel, twenty rules
│   ├── security-alerting/  metric filters and alarms
│   └── secret/             generated credential in Secrets Manager
├── task1-terraform-module/
│   └── bootstrap/          creates the state bucket and lock table
├── task2-aws-security/
├── task3-lambda-troubleshooting/
│   ├── original/           the broken files, unmodified, with provenance
│   ├── terraform/ lambda/ tests/
│   └── FIXES.md            eight defects, cause and fix for each
├── docs/                   the brief, its translation, and the design spec
└── .github/workflows/ci.yml
```

Each task has its own README with prerequisites, how to run it, and the design
choices behind it.

## Prerequisites

- Terraform >= 1.9
- Python 3.12 or newer, for the Task 3 tests
- AWS credentials, only if you intend to apply. Nothing here needs them to
  validate.

Optional, for the same checks CI runs:

```bash
brew install tflint checkov
```

## Security groups

This was a specific requirement, and it drove the shared
[`modules/security-group/`](modules/security-group/).

Every rule is its own Terraform resource, addressed by a human-written name:

```hcl
ingress_rules = {
  "https-from-office-lisbon" = { ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "203.0.113.10/32", description = "..." }
  "https-from-office-porto"  = { ip_protocol = "tcp", from_port = 443, to_port = 443, cidr_ipv4 = "198.51.100.7/32",  description = "..." }
}
```

Remove the Porto entry and the plan is one line:

```
# module.web_sg.aws_vpc_security_group_ingress_rule.this["https-from-office-porto"] will be destroyed

Plan: 0 to add, 0 to change, 1 to destroy.
```

The security group and the Lisbon rule do not appear, because they did not
change. The two common alternatives both fail that test: inline `ingress`
blocks rewrite the whole attribute, and `count` over a list shifts every index
after the one removed, so taking out one rule destroys and recreates three.

The module's README has the full comparison and the reasoning.

## Verification

Nothing in this repository has been applied to a live AWS account. The
deliverable is validated code, and this is what backs that claim:

```bash
terraform fmt -check -recursive

for dir in task1-terraform-module task1-terraform-module/bootstrap \
           task2-aws-security task3-lambda-troubleshooting/terraform \
           modules/security-group modules/kms-key; do
  terraform -chdir="$dir" init -backend=false -input=false
  TF_WORKSPACE=staging terraform -chdir="$dir" validate
done

TF_WORKSPACE=staging tflint --recursive --minimum-failure-severity=warning
checkov   # reads .checkov.yaml

cd task3-lambda-troubleshooting
python3 -m venv .venv && . .venv/bin/activate
pip install -r tests/requirements.txt
pytest tests -v
```

Current state:

| Check | Result |
|---|---|
| `terraform fmt -check -recursive` | clean |
| `terraform validate`, six configurations | all pass |
| `tflint --recursive` | no findings |
| `checkov` | 382 passed, 0 failed, 26 skipped |
| `pytest` | 8 passed |

Every checkov skip is an inline `#checkov:skip` next to the code it applies to,
with the reason written out. There is no central suppression list, because that
is where exceptions go to be forgotten. The substantive ones are explained in
[`task2-aws-security/README.md`](task2-aws-security/README.md#verification).

`.checkov.yaml` and `task3-lambda-troubleshooting/original/.tflint.hcl` exclude
one directory from both tools: the challenge's original broken files, kept
unmodified as the evidence behind `FIXES.md`. Linting them would report the
very defects that document explains, and hardening them would destroy the
before-and-after it depends on.

`TF_WORKSPACE=staging` is needed because Task 1 indexes its per-environment
settings by workspace name and deliberately has no entry for `default`. An
unknown workspace fails at plan time rather than deploying the wrong sizing.

CI runs all of the above on every pull request. Actions are pinned to commit
SHAs rather than tags, since a tag can be moved.

## Assumptions

Stated so a reviewer does not have to guess:

- **Region `eu-west-1`** for Tasks 1 and 2. Task 3 stays on `us-east-1`,
  because the challenge forbids changing its provider settings.
- **Nothing is applied.** No AWS account was used. Where a claim would need a
  real apply to prove, it is labelled as such rather than asserted. Task 3's
  IAM policy is the clearest example: the tests cover the handler, and the
  policy is reviewed statement by statement in `FIXES.md`.
- **One account, several environments.** Task 1 uses workspaces, which is the
  bonus as the challenge words it. Separate accounts per environment would want
  separate configurations; `task1-terraform-module/locals.tf` is where that
  decision would be revisited.
- **The root user cannot be disabled by Terraform**, or by any AWS API. Task 2
  covers the part that is codifiable: two AWS Config rules that report on root
  MFA and root access keys, and a CloudWatch alarm that fires the moment root
  does anything.
- **Task 3's upstream repository is gone.** The original broken files come from
  a public copy's first commit, preserved verbatim in
  `task3-lambda-troubleshooting/original/` with instructions to verify.

## Design notes

The decisions worth arguing about, and where each is argued:

| Decision | Where |
|---|---|
| One resource per security group rule | [`modules/security-group/README.md`](modules/security-group/README.md) |
| Customer-managed KMS keys, one per purpose | [`modules/kms-key/README.md`](modules/kms-key/README.md) |
| Workspaces rather than a directory per environment | [`task1-terraform-module/README.md`](task1-terraform-module/README.md#design-choices) |
| `ignore_changes = [ami]` on instances | [`task1-terraform-module/README.md`](task1-terraform-module/README.md#design-choices) |
| SSM Session Manager rather than a bastion on port 22 | [`task2-aws-security/README.md`](task2-aws-security/README.md#compute) |
| Pinning provider versions in Task 3 despite the constraint | [`task3-lambda-troubleshooting/FIXES.md`](task3-lambda-troubleshooting/FIXES.md#7-nothing-pinned-the-provider-version) |

The design this was built from is in
[`docs/superpowers/specs/`](docs/superpowers/specs/).
