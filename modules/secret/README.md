# secret

A generated credential in Secrets Manager. Nobody ever types it or sees it.

## Usage

```hcl
module "app_secret" {
  source = "git::https://github.com/JPLima/devops.git//modules/secret?ref=v1.1.0"

  name        = "myapp/application/database"
  description = "Database credential for the myapp application"
  username    = "appuser"
  kms_key_arn = module.secrets_key.arn

  tags = { Project = "myapp" }
}
```

Grant an instance read access to that one secret:

```hcl
module "iam" {
  source = "git::https://github.com/JPLima/devops.git//modules/iam-instance-role?ref=v1.1.0"

  secret_arns = [module.app_secret.secret_arn]
  # ...
}
```

The key needs `secretsmanager.amazonaws.com` in its `service_principals`.

## The stored value

A JSON document, which is the shape the AWS SDKs and RDS rotation lambdas
expect:

```json
{ "username": "appuser", "password": "<generated>" }
```

Read it at runtime rather than baking it into an image or an environment
variable:

```bash
aws secretsmanager get-secret-value \
  --secret-id myapp/application/database \
  --query SecretString --output text | jq -r .password
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name of the secret. Slashes give it a hierarchy. |
| `description` | `string` | required | What the secret holds. |
| `kms_key_arn` | `string` | required | Key encrypting the secret. |
| `username` | `string` | required | Username stored alongside the generated password. |
| `password_length` | `number` | `32` | Length of the generated password. |
| `recovery_window_in_days` | `number` | `30` | Days a deleted secret can be restored. |
| `tags` | `map(string)` | `{}` | Tags applied to the secret. |

## Outputs

| Name | Description |
|---|---|
| `secret_arn` | ARN of the secret, for granting read access in an IAM policy. |
| `secret_name` | Name of the secret. |
| `username` | The username. The password is deliberately not an output. |

## Notes

**The password is still in Terraform state.** This is the caveat worth being
honest about: `random_password` keeps its result in state like any other
attribute. Secrets Manager wins on rotation, access control and audit, not on
keeping the value out of state entirely. Only a rotation lambda that replaces
the initial value achieves that. Encrypt your state bucket accordingly.

**`secret_string` is under `ignore_changes`.** Once a rotation lambda takes
over it writes new versions, and without this every apply would overwrite the
rotated value with the original one.

**`random_password` has no `keepers`.** The password must not change on its
own. Rotation is an explicit act, not a side effect of an unrelated apply.

**`override_special` excludes the awkward characters.** What remains survives a
shell, a connection string and a YAML file without an argument about quoting.

**A deleted secret is not gone for 30 days, and its name is reserved that whole
time.** Recreating a secret with the same name inside the recovery window
fails. Use `recovery_window_in_days = 0` in a throwaway environment if you plan
to destroy and reapply.
