# security-alerting

Metric filters and CloudWatch alarms over a CloudTrail log group, plus the SNS
topic they publish to.

CloudTrail records everything and alerts on nothing. This module is the part
that turns a log into a signal.

## Usage

```hcl
module "alerting" {
  source = "git::https://github.com/JPLima/devops.git//modules/security-alerting?ref=v1.1.0"

  name           = "myapp"
  log_group_name = module.logging.log_group_name
  kms_key_arn    = module.observability_key.arn

  notification_emails = ["security@example.com"]

  tags = { Project = "myapp" }
}
```

Each address gets a confirmation email it has to click. Terraform cannot
confirm a subscription on someone's behalf, so a freshly applied topic delivers
nothing until they do.

Requires the [`cloudtrail`](../cloudtrail/) module, or any trail configured to
write to CloudWatch Logs. Metric filters read a log group, not S3.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for the topic, filters and alarms. |
| `log_group_name` | `string` | required | CloudTrail log group the filters read. |
| `kms_key_arn` | `string` | required | Key encrypting the SNS topic. |
| `notification_emails` | `list(string)` | `[]` | Addresses subscribed to the topic. |
| `metric_namespace` | `string` | `"Security"` | CloudWatch namespace for the metrics. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `topic_arn` | SNS topic the alarms publish to. |
| `alarm_names` | Map of detection name to CloudWatch alarm name. |
| `metric_filter_names` | Map of detection name to metric filter name. |

## The detections

| Key | Fires when | Threshold |
|---|---|---|
| `unauthorized-api-calls` | Calls are denied. In volume, this is someone probing. | 5 in 5 minutes |
| `root-account-usage` | The root user does anything at all. | 1 |
| `console-login-without-mfa` | A console sign-in succeeds without MFA. | 1 |
| `iam-policy-changes` | Any policy is created, attached, changed or deleted. | 1 |
| `cloudtrail-config-changes` | The trail is changed, stopped or deleted. | 1 |
| `security-group-changes` | A rule is authorised or revoked outside Terraform. | 1 |

Adding a detection is one entry in `local.alarms` in `main.tf`: a pattern, a
threshold and a description. The metric filter and the alarm are generated from
it, so nothing that already exists is touched.

## Notes

**Every metric transformation sets `default_value = 0`.** Without it the metric
has no datapoint when nothing matches, and the alarm sits in
`INSUFFICIENT_DATA` rather than `OK`. An alarm you cannot tell apart from a
broken alarm is not monitoring.

**`cloudtrail-config-changes` is the one that matters most.** Stopping the
trail is what covering tracks looks like, and it is the alarm an attacker would
disable first. Consider forwarding this topic somewhere outside the account.

**`security-group-changes` will page on your own applies.** That is intentional:
a rule changed outside Terraform and a rule changed by Terraform look identical
in CloudTrail, and only one of them is fine. If the noise is too much, filter
on `userIdentity` rather than raising the threshold.

**Alarms also fire `ok_actions`.** You get told when a condition clears, not
just when it starts.

**Patterns are CloudWatch Logs filter syntax, not JSONPath.** Test a change
with `aws logs filter-log-events --filter-pattern` against the real group
before relying on it; a pattern that matches nothing fails silently.
