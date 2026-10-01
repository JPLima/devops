# iam-instance-role

An EC2 instance role and profile, written as least privilege rather than
assembled from managed policies.

Scoped to one bucket, one key prefix and one KMS key. There is no
`Resource = "*"` in the policy it generates.

## Usage

```hcl
module "iam" {
  source = "git::https://github.com/JPLima/devops.git//modules/iam-instance-role?ref=v1.1.0"

  name            = "myapp-app"
  data_bucket_arn = aws_s3_bucket.data.arn
  kms_key_arn     = module.data_key.arn
  secret_arns     = [module.app_secret.secret_arn]

  tags = { Project = "myapp" }
}

module "app" {
  source = "git::https://github.com/JPLima/devops.git//modules/ec2?ref=v1.1.0"

  iam_instance_profile = module.iam.instance_profile_name
  # ...
}
```

Narrow the bucket access further when the workload only owns part of a bucket:

```hcl
data_bucket_prefix = "uploads/*"
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for the role, policy and instance profile. |
| `data_bucket_arn` | `string` | required | The one bucket this instance may read and write. |
| `kms_key_arn` | `string` | required | Key encrypting that bucket. |
| `data_bucket_prefix` | `string` | `"*"` | Key prefix inside the bucket the instance may touch. |
| `secret_arns` | `list(string)` | `[]` | Secrets Manager secrets the instance may read. |
| `tags` | `map(string)` | `{}` | Tags applied to the role. |

## Outputs

| Name | Description |
|---|---|
| `role_arn` | ARN of the instance role. |
| `role_name` | Name of the instance role. |
| `instance_profile_name` | Profile to pass to the `ec2` module. |
| `policy_arn` | ARN of the hand-written workload policy. |

## What the policy grants

| Statement | Actions | Resource |
|---|---|---|
| `ReadWriteOwnObjects` | `s3:GetObject`, `PutObject`, `DeleteObject` | `<bucket>/<prefix>` |
| `ListOwnPrefix` | `s3:ListBucket` | the bucket, conditioned on `s3:prefix` |
| `UseBucketKey` | `kms:Decrypt`, `GenerateDataKey` | the key, conditioned on `kms:ViaService` being S3 |
| `ReadOwnSecrets` | `secretsmanager:GetSecretValue` | only the ARNs you pass |

Plus one managed policy: `AmazonSSMManagedInstanceCore`.

## Notes

**The KMS statement is easy to forget.** Without it, `GetObject` and
`PutObject` against an encrypted bucket return `AccessDenied`, and the error
names S3 rather than KMS.

**`ListBucket` needs the bucket ARN without a key suffix.** It is a
bucket-level action, so the `s3:prefix` condition is what keeps the listing
narrow rather than the resource ARN.

**`AmazonSSMManagedInstanceCore` is the one managed policy.** It is the
documented contract for Session Manager and changes as the agent does.
Everything else is written out.

**`max_session_duration` is one hour.** The metadata service rotates instance
credentials anyway, and a shorter ceiling limits how long a leaked set works.
