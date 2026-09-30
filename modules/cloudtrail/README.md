# cloudtrail

A multi-region CloudTrail trail with log file validation, delivering to both an
S3 bucket and a CloudWatch log group.

S3 is the durable copy. CloudWatch is what metric filters and alarms can read
in near real time, which is what the [`security-alerting`](../security-alerting/)
module attaches to.

## Usage

```hcl
module "logging" {
  source = "git::https://github.com/JPLima/devops.git//modules/cloudtrail?ref=v1.1.0"

  name        = "myapp"
  bucket_name = "myapp-cloudtrail-${data.aws_caller_identity.current.account_id}"
  kms_key_arn = module.observability_key.arn

  tags = { Project = "myapp" }
}
```

The key needs a grant for the CloudTrail and CloudWatch Logs service
principals, which services cannot get through a role:

```hcl
module "observability_key" {
  source = "git::https://github.com/JPLima/devops.git//modules/kms-key?ref=v1.1.0"

  alias       = "myapp-observability"
  description = "Encrypts CloudTrail and its log group"

  service_principals = [
    "cloudtrail.amazonaws.com",
    "logs.eu-west-1.amazonaws.com",
  ]
}
```

Bucket names are a single global namespace, so suffix yours with the account
id. That keeps it stable across a state rebuild, where a random suffix would
not.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for the trail and its resources. |
| `bucket_name` | `string` | required | Globally unique name for the destination bucket. |
| `kms_key_arn` | `string` | required | Key encrypting the trail's objects and its log group. |
| `log_retention_days` | `number` | `365` | Retention for the CloudWatch log group. |
| `s3_expiration_days` | `number` | `730` | Days before trail objects expire. Zero keeps them forever. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `trail_arn` | ARN of the trail. |
| `trail_name` | Name of the trail. |
| `bucket_name` | Bucket receiving trail objects. |
| `bucket_arn` | ARN of that bucket. |
| `log_group_name` | Log group the trail writes to. Metric filters attach here. |
| `log_group_arn` | ARN of that log group. |

## What it creates

The trail, its destination bucket (versioned, SSE-KMS, public access blocked,
ACLs disabled, TLS enforced, lifecycle to Standard-IA at 90 days and Glacier at
180), a bucket policy scoped to this account's trail, a CloudWatch log group,
and the role CloudTrail assumes to write to it.

## Notes

**`is_multi_region_trail` is hardcoded true.** A single-region trail is a blind
spot: an attacker who knows which region you watch simply uses another one.

**`include_global_service_events` is hardcoded true.** IAM and other global
services report into one region only. Without this those events are simply
absent, which is the opposite of what an audit trail is for.

**`enable_log_file_validation` is hardcoded true.** It signs each delivered
file, so tampering after delivery is detectable.

**Advanced event selectors capture S3 data events as well as management
events.** Management events alone record that a bucket was created, not that
its contents were read. Data events are billed per event, so this is the line
to revisit if the trail gets expensive.

**The bucket policy conditions on `aws:SourceArn`.** Without it, the bucket
would accept deliveries from any account's trail, which is a confused deputy
waiting to happen.

**`prevent_destroy` is set on the bucket.** An audit trail you can delete by
accident is not an audit trail. `terraform destroy` will fail until someone
removes the lifecycle block, which is the intended friction.

**One trail per account and region.** AWS allows five, but the free tier covers
one copy of management events. A second trail on the same events bills for
every one.
