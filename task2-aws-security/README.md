# Task 2: AWS cloud security

A private workload with the controls the challenge asks for: a segmented
network, an instance with no inbound access, least-privilege IAM, encryption on
everything that stores data, CloudTrail, AWS Config, and alarms that fire on
events worth waking someone for.

## Prerequisites

- Terraform >= 1.9
- AWS credentials with permission to create VPC, EC2, IAM, KMS, S3, CloudTrail,
  Config, CloudWatch, SNS and Secrets Manager resources
- An account where AWS Config is not already recording. Config allows one
  recorder per region, so an existing one has to be imported or removed first

## Deploying

```bash
terraform init
terraform plan
terraform apply
```

To receive the alarms, pass addresses. Each recipient gets a confirmation email
they have to click; Terraform cannot confirm a subscription for them.

```bash
terraform apply -var='security_notification_emails=["you@example.com"]'
```

Then connect to the instance. There is no SSH:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

## Layout

```
task2-aws-security/
├── main.tf              wires the modules and holds the data bucket
├── locals.tf            name prefix and bucket suffix
├── variables.tf
├── outputs.tf
└── versions.tf
```

There is no `modules/` directory here. Every module lives once at the
repository root and is consumed by git URL at a version tag:

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.0.0"
  ...
}
```

This task uses `vpc`, `ec2`, `security-group`, `kms-key` (three times, one key
per purpose), `iam-instance-role`, `cloudtrail`, `aws-config`,
`security-alerting` and `secret`.

The `vpc` and `ec2` modules are the same ones Task 1 uses. What makes this
design private is configuration, not different code:
`map_public_ip_on_launch = false`, `associate_public_ip_address = false`, flow
logs on, three interface endpoints and the S3 gateway endpoint. See
[`../modules/README.md`](../modules/README.md).

## Security practices implemented

### Network

Public subnets hold the NAT gateways and nothing else. `map_public_ip_on_launch`
is false even there, so nothing acquires a public address by accident.

The private subnets reach AWS APIs through VPC endpoints: interface endpoints
for `ssm`, `ssmmessages` and `ec2messages`, and a gateway endpoint for S3. That
traffic never traverses the NAT gateway or the public internet. The gateway
endpoint is also free, where an interface endpoint for S3 would bill per hour
and per gigabyte.

VPC Flow Logs capture `ALL` traffic, not just rejects. Accepted traffic is what
tells you what an intruder reached; rejects only tell you what they failed to
reach. The log group is encrypted with a customer-managed key and its IAM role
is scoped to that one group.

### Compute

The instance sits in a private subnet with `associate_public_ip_address = false`
and a security group with **no ingress rules at all**.

Administrative access is Session Manager. This is the honest answer to "only
necessary ports": the number of necessary inbound ports is zero. A bastion on
port 22 would add a host to patch, a key pair to distribute and revoke, and an
audit trail that lives in `sshd` logs rather than CloudTrail. With SSM, every
session is a CloudTrail event and access is an IAM decision.

Egress is scoped to the VPC CIDR on port 443, so a compromised instance cannot
call out to an arbitrary address.

IMDSv2 is required with a hop limit of 1. Version 1 answers an unauthenticated
`GET`, which is how a server-side request forgery bug in an application turns
into leaked role credentials. The hop limit stops a container on the host from
reaching the metadata service through the bridge.

### IAM

The workload policy is written by hand as an `aws_iam_policy_document`, scoped
to one bucket, one prefix and one key. There is no `Resource = "*"` in it.

The one managed policy attached is `AmazonSSMManagedInstanceCore`, which is the
documented contract for Session Manager. Hand-writing it would drift from AWS
as the agent changes, which is the case where a managed policy is the right
answer.

One detail worth naming: the policy grants `kms:Decrypt` and
`kms:GenerateDataKey` on the bucket's key, conditioned on `kms:ViaService`
being S3. Without the KMS grant, every `GetObject` against the encrypted bucket
returns `AccessDenied`, and the error names S3 rather than KMS.

### Encryption

Three customer-managed KMS keys, all with rotation enabled:

| Key | Encrypts |
|---|---|
| `observability` | CloudTrail objects, its log group, VPC flow logs, AWS Config data |
| `data` | EBS root volume, application data bucket |
| `secrets` | Secrets Manager secrets |

A key per purpose keeps each key policy readable and means revoking access to
logs does not also lock the workload out of its own data.

Every bucket has SSE-KMS by default, versioning, public access blocked and
`BucketOwnerEnforced` ownership, which disables ACLs entirely. Each bucket
policy denies non-TLS requests, and the data bucket additionally denies a
`PutObject` that asks for any key but ours.

### Audit

CloudTrail is multi-region with global service events included and log file
validation enabled. A single-region trail is a blind spot: an attacker who
knows which region you watch uses another one. IAM and other global services
report into one region only, so without `include_global_service_events` those
events are simply absent.

The trail writes to both S3 (durable, lifecycle-managed, transitioned to
Glacier after 180 days) and CloudWatch Logs (readable in near real time, which
is what metric filters need).

Advanced event selectors capture data events for S3 objects as well as
management events. Management events alone record that a bucket was created,
not that its contents were read.

### Detection

CloudTrail records everything and alerts on nothing. `security-alerting` is the
part that turns a log into a signal. Six metric filters, each with an alarm:

| Detection | Fires when |
|---|---|
| `unauthorized-api-calls` | 5 or more denied calls in 5 minutes |
| `root-account-usage` | The root user does anything |
| `console-login-without-mfa` | A console sign-in succeeds without MFA |
| `iam-policy-changes` | Any policy is created, attached, changed or deleted |
| `cloudtrail-config-changes` | The trail is changed, stopped or deleted |
| `security-group-changes` | A rule is authorised or revoked outside Terraform |

Each metric transformation sets `default_value = 0`. Without it the metric has
no datapoint when nothing matches, and the alarm sits in `INSUFFICIENT_DATA`
rather than `OK`. An alarm you cannot tell apart from a broken alarm is not
monitoring.

### Configuration recording

AWS Config records every supported resource type including global ones, and
evaluates 20 managed rules. CloudTrail answers "who changed this"; Config
answers "what does it look like now, and is that acceptable". Different
questions, which is why both are here.

### Secrets

The database credential is generated by `random_password` and written straight
to Secrets Manager. Nobody ever types it or sees it. The instance role may read
that one secret ARN.

The honest caveat, stated in the module: `random_password` keeps its result in
Terraform state as well. Secrets Manager wins on rotation, access control and
audit, not on keeping the value out of state entirely. Only a rotation lambda
that replaces the initial value achieves that.

## The root user

The challenge lists "disable root user" as a best practice. It cannot be done
through Terraform, or through any AWS API. Rather than pretend otherwise, this
configuration covers the part that is codifiable:

- `root-account-mfa-enabled`, a Config rule that reports whether root has MFA
- `root-access-key-check`, a Config rule that reports whether root has access keys
- `root-account-usage`, a CloudWatch alarm that fires the moment root does anything

Removing root access keys and enabling MFA on root are console actions someone
has to perform once. These three controls tell you whether that happened and
whether it stayed that way.

## Verification

```bash
terraform fmt -check -recursive
terraform init -backend=false && terraform validate
tflint --recursive
checkov -d . --framework terraform
```

Checkov passes with no failures. The skipped checks each carry an inline
`#checkov:skip` and a reason. The substantive ones:

- **`CKV_AWS_109`, `CKV_AWS_111`, `CKV_AWS_356` on the KMS key policy.** Every
  key policy needs a statement granting the account root `kms:*` on `*`. IAM
  policies alone cannot grant access to a KMS key, so without it the key
  becomes unmanageable and AWS support is the only way back. A key policy's
  `Resource` is always `*`, meaning that key; there is no narrower form.
- **`CKV_AWS_252`, CloudTrail should define an SNS topic.** `sns_topic_name`
  notifies once per delivered log file, which is noise. Detection runs off the
  CloudWatch log group through the metric filters in `security-alerting`.
- **`CKV_AWS_394`, pin availability zone identity.** Pinning zone ids would tie
  the module to one region. The `opt-in-status` filter excludes Local Zones and
  Wavelength zones, which is the result-set expansion that actually matters.

## Design choices

**No bastion host.** Discussed above. The trade-off is a hard dependency on the
SSM agent and the three interface endpoints; if the agent is broken the
instance is unreachable. The answer to that is to replace the instance, which
is the right instinct for cattle anyway.

**Three KMS keys rather than one.** Blast radius, and readable key policies.

**Buckets are declared where they are used.** The trail bucket lives in the
`cloudtrail` module and the Config bucket in `aws-config`, because each needs
a service-specific bucket policy that would turn a shared bucket module into a
passthrough for arbitrary policy statements. The application data bucket is in
`main.tf` because it belongs to the root module's own composition.

**The `ec2` module does not create its security group.** Task 1 needs a group
allowing HTTPS from named networks; Task 2 needs one with no ingress at all.
Expressing both through a flag on the module would mean a module that
sometimes owns a security group and sometimes does not, with outputs that are
sometimes null. Composing them in `main.tf` from the `security-group` module is
one way to do it instead of two, and it means the group outlives any particular
instance.

**`prevent_destroy` on the CloudTrail bucket.** An audit trail you can delete
by accident is not an audit trail. It does mean `terraform destroy` fails until
someone removes the lifecycle block, which is the intended friction.

**Bucket names are suffixed with the account id rather than a random id.** S3
names are a single global namespace, so they need a suffix. The account id
makes the name stable across a state rebuild; `random_id` would not.
