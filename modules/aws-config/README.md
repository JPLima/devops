# aws-config

An AWS Config recorder, its delivery channel, and twenty managed rules.

CloudTrail answers "who changed this". Config answers "what does it look like
right now, and is that acceptable". Different questions, which is why a secure
baseline wants both.

## Usage

```hcl
module "config" {
  source = "git::https://github.com/JPLima/devops.git//modules/aws-config?ref=v1.1.0"

  name        = "myapp"
  bucket_name = "myapp-config-${data.aws_caller_identity.current.account_id}"
  kms_key_arn = module.observability_key.arn

  tags = { Project = "myapp" }
}
```

The key needs `config.amazonaws.com` in its `service_principals`.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for the recorder, channel and rules. |
| `bucket_name` | `string` | required | Globally unique name for the delivery bucket. |
| `kms_key_arn` | `string` | required | Key encrypting the delivery bucket. |
| `expiration_days` | `number` | `365` | Days before configuration snapshots expire. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `recorder_name` | Name of the configuration recorder. |
| `bucket_name` | Bucket Config delivers snapshots to. |
| `role_arn` | ARN of the role Config assumes. |
| `rule_names` | Map of short rule name to deployed rule name. |

## The rules

| Key | AWS managed rule |
|---|---|
| `root-account-mfa-enabled` | `ROOT_ACCOUNT_MFA_ENABLED` |
| `root-access-key-check` | `IAM_ROOT_ACCESS_KEY_CHECK` |
| `iam-user-mfa-enabled` | `IAM_USER_MFA_ENABLED` |
| `encrypted-volumes` | `ENCRYPTED_VOLUMES` |
| `ec2-imdsv2-check` | `EC2_IMDSV2_CHECK` |
| `ec2-no-public-ip` | `EC2_INSTANCE_NO_PUBLIC_IP` |
| `rds-storage-encrypted` | `RDS_STORAGE_ENCRYPTED` |
| `rds-not-public` | `RDS_INSTANCE_PUBLIC_ACCESS_CHECK` |
| `s3-encryption-enabled` | `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED` |
| `s3-public-read-prohibited` | `S3_BUCKET_PUBLIC_READ_PROHIBITED` |
| `s3-public-write-prohibited` | `S3_BUCKET_PUBLIC_WRITE_PROHIBITED` |
| `s3-ssl-requests-only` | `S3_BUCKET_SSL_REQUESTS_ONLY` |
| `cloudtrail-enabled` | `CLOUD_TRAIL_ENABLED` |
| `cloudtrail-log-validation` | `CLOUD_TRAIL_LOG_FILE_VALIDATION_ENABLED` |
| `cloudtrail-encryption` | `CLOUD_TRAIL_ENCRYPTION_ENABLED` |
| `vpc-flow-logs-enabled` | `VPC_FLOW_LOGS_ENABLED` |
| `restricted-ssh` | `INCOMING_SSH_DISABLED` |
| `sg-no-unrestricted-ingress` | `VPC_SG_OPEN_ONLY_TO_AUTHORIZED_PORTS` |
| `kms-key-rotation-enabled` | `CMK_BACKING_KEY_ROTATION_ENABLED` |
| `secretsmanager-kms-encrypted` | `SECRETSMANAGER_USING_CMK` |

Adding a check is one entry in `local.rules` in `main.tf`.

## Notes

**One recorder per region, per account.** AWS allows exactly one. If the
account already has one, this module's apply fails; import the existing
recorder or remove it first. That is the most common reason this module does
not apply cleanly on a first try.

**Creating a recorder does not start it.** `aws_config_configuration_recorder_status`
is what enables recording. Without that resource, Config records nothing and
every rule reports `NOT_APPLICABLE` while looking correctly configured.

**Rules depend on the recorder being enabled.** A rule created before the
recorder is running is rejected by the API, which is why the `depends_on` is
there.

**It records all supported types, including global ones.** Recording a subset
is how a resource type becomes invisible the day it matters. Global resources
such as IAM should only be recorded in one region, so set
`include_global_resource_types = false` if you deploy this to a second one.

**The root user cannot be disabled by Terraform, or by any AWS API.** The first
two rules are the codifiable part: they report whether root has MFA and whether
it has access keys. Pair them with the `root-account-usage` alarm in
[`security-alerting`](../security-alerting/).

## Cost

Config bills per configuration item recorded and per rule evaluation. In an
account with a lot of churn, `all_supported = true` plus twenty rules is not
free. Check Cost Explorer after the first month.
