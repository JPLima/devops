# kms-key

A customer-managed KMS key with rotation on, an alias, and a key policy that
grants the account root what it must have and services only what they need.

Shared by all three tasks.

## Why not the AWS-managed key

Every service here would encrypt with an AWS-managed key if given nothing. The
data is just as encrypted. What you lose is everything around it:

| | AWS-managed key | Customer-managed key |
|---|---|---|
| Key policy | Not visible, not editable | Yours, and auditable |
| Rotation | Yearly, fixed | Configurable, and provable |
| Cross-account grants | Impossible | Possible |
| Revoking access | No mechanism | Edit the policy |
| Cost | Free | ~$1/month per key |

A dollar a month is the price of being able to answer "who can decrypt this"
with a policy document rather than a shrug.

## Usage

Storage that authorises through IAM (EBS, S3 with SSE-KMS, RDS) needs no
service grant at all. The account root statement is enough:

```hcl
module "data_key" {
  source = "../modules/kms-key"

  alias       = "myproject-data"
  description = "Encrypts EBS volumes and the application data bucket"

  tags = local.tags
}
```

Services that act on their own behalf cannot assume a role, so they need a
grant in the key policy itself:

```hcl
module "observability_key" {
  source = "../modules/kms-key"

  alias       = "myproject-observability"
  description = "Encrypts CloudTrail, VPC flow logs and AWS Config data"

  service_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "logs.eu-west-1.amazonaws.com",
    "delivery.logs.amazonaws.com",
  ]

  tags = local.tags
}
```

Narrow that grant with a condition when you can:

```hcl
service_condition = {
  test     = "ArnLike"
  variable = "kms:EncryptionContext:aws:logs:arn"
  values   = ["arn:aws:logs:eu-west-1:123456789012:log-group:*"]
}
```

## The account root statement

Every key this module creates starts with:

```hcl
principals { type = "AWS", identifiers = ["arn:aws:iam::<account>:root"] }
actions   = ["kms:*"]
resources = ["*"]
```

This looks alarming and is mandatory. KMS is one of the few services where an
IAM policy alone cannot grant access: the key policy has to delegate to IAM
first. Omit this statement and the key becomes unmanageable by anyone,
including the account that owns it, and AWS support is the only way back.

`Resource = "*"` in a key policy means *this key*. There is no narrower form,
because a key policy is attached to exactly one key.

This is why the module carries `#checkov:skip` for `CKV_AWS_109`,
`CKV_AWS_111` and `CKV_AWS_356`, each with that reasoning inline.

## What the service grant does not include

The service statement allows `Encrypt`, `Decrypt`, `ReEncrypt*`,
`GenerateDataKey*`, `DescribeKey` and `CreateGrant`. It does not allow
`ScheduleKeyDeletion`, `DisableKey`, `PutKeyPolicy` or anything else
administrative. A service needs to use a key, never to destroy one.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `alias` | `string` | required | Alias without the `alias/` prefix. |
| `description` | `string` | required | What this key encrypts. |
| `service_principals` | `list(string)` | `[]` | AWS services allowed to use the key. |
| `service_condition` | `object` | `null` | Optional condition narrowing that grant. |
| `deletion_window_in_days` | `number` | `30` | Waiting period before a scheduled deletion takes effect. |
| `tags` | `map(string)` | `{}` | Tags applied to the key. |

## Outputs

| Name | Description |
|---|---|
| `arn` | Key ARN, which is what most resources expect. |
| `key_id` | Key id. |
| `alias` | Full alias, including the `alias/` prefix. |

## Notes

Rotation is always on and is not a variable. A key you cannot rotate is a key
you will still be using in five years.

The default deletion window is 30 days rather than the 7-day minimum. A
scheduled deletion is reversible until it completes, and a month is a better
window in which to notice that something still needed the key.

Keys are cheap. Prefer one per purpose over one shared everywhere: the key
policy stays readable, and revoking access to logs does not also lock a
workload out of its own data.
