# DevOps Code Challenge

| Task | | |
|---|---|---|
| 1 | VPC, EC2 and RDS from modules, S3 backend with DynamoDB locking, environments as workspaces | [`task1-terraform-module/`](task1-terraform-module/) |
| 2 | Private workload, least-privilege IAM, encryption, CloudTrail, Config, alarms | [`task2-aws-security/`](task2-aws-security/) |
| 3 | A broken Lambda and Terraform project, fixed | [`task3-lambda-troubleshooting/`](task3-lambda-troubleshooting/) |

Each task has its own README. Task 3's writeup is [`FIXES.md`](task3-lambda-troubleshooting/FIXES.md).

## Modules

Every module lives once, in [`modules/`](modules/). No task has a `modules/`
directory of its own. They are consumed by git URL at a tag:

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.1.0"
  ...
}
```

| Module | Task 1 | Task 2 | Task 3 |
|---|:---:|:---:|:---:|
| [`security-group`](modules/security-group/) | yes | yes | |
| [`kms-key`](modules/kms-key/) | yes | yes | |
| [`vpc`](modules/vpc/) | yes | yes | |
| [`ec2`](modules/ec2/) | yes | yes | |
| [`rds`](modules/rds/) | yes | | |
| [`iam-instance-role`](modules/iam-instance-role/) | | yes | |
| [`cloudtrail`](modules/cloudtrail/) | | yes | |
| [`aws-config`](modules/aws-config/) | | yes | |
| [`security-alerting`](modules/security-alerting/) | | yes | |
| [`secret`](modules/secret/) | | yes | |

`vpc` and `ec2` serve both the public web tier in Task 1 and the private
workload in Task 2. See [`modules/README.md`](modules/README.md) for the
versioning scheme and its drawback.

Task 3 uses none of them. Its brief limits it to the AWS services the broken
project already used, so it stays self-contained.

## Security groups

Every rule is its own resource, keyed by name:

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

Inline `ingress` blocks rewrite the whole attribute instead, and `count` over a
list shifts every index after the one removed. Details and the plan diff that
shows it in [`modules/security-group/README.md`](modules/security-group/README.md).

## Prerequisites

Terraform >= 1.9, and Python 3.12+ for the Task 3 tests. AWS credentials only
if you intend to apply. Optionally `brew install tflint checkov` for the checks
CI runs.

## Checks

```bash
terraform fmt -check -recursive

for dir in task1-terraform-module task1-terraform-module/bootstrap \
           task2-aws-security task3-lambda-troubleshooting/terraform; do
  terraform -chdir="$dir" init -backend=false -input=false
  TF_WORKSPACE=staging terraform -chdir="$dir" validate
done

for dir in modules/*/; do
  terraform -chdir="$dir" init -backend=false -input=false
  terraform -chdir="$dir" validate
done

TF_WORKSPACE=staging tflint --recursive --minimum-failure-severity=warning
checkov

cd task3-lambda-troubleshooting
python3 -m venv .venv && . .venv/bin/activate
pip install -r tests/requirements.txt
pytest tests
```

`TF_WORKSPACE` is needed because Task 1 has no settings for the `default`
workspace on purpose. `init` on a root fetches the modules from the tag, so it
needs network access.

Currently: fmt clean, 4 roots and 10 modules validate, tflint reports nothing,
checkov 281 passed and 0 failed, 8 tests pass. CI runs the same on every pull
request, with actions pinned to SHAs.

## Notes

Nothing here has been applied. All three configurations plan cleanly against a
real account (33, 110 and 13 resources), and the security group behaviour above
was checked by diffing the addresses of two plans, but no infrastructure was
created.

Region is `eu-west-1`, except Task 3, which stays on `us-east-1` because the
challenge forbids touching its provider block.

The root user cannot be disabled through Terraform or any AWS API. Task 2 does
the part that can be codified: Config rules for root MFA and root access keys,
plus an alarm on any root activity.

Task 3's upstream repository no longer exists. The original broken files come
from the first commit of a public copy and are preserved in
[`task3-lambda-troubleshooting/original/`](task3-lambda-troubleshooting/original/)
with instructions to verify them.

Checkov skips are inline, each with a reason, except `CKV_TF_1` which is a
repository-wide decision explained in `.checkov.yaml`.
