# Changelog

All modules share one version. Tags are `vMAJOR.MINOR.PATCH`.

- **MAJOR** a breaking change to a module's inputs or outputs
- **MINOR** a backwards-compatible addition
- **PATCH** a fix that changes no inputs or outputs

## v1.1.0

### Changed

- `rds`: `multi_az` now defaults to `true`.

  High availability should be something you opt out of for a throwaway
  environment, not something you remember to opt into for a production one.
  Backwards compatible in the sense that no input was removed or renamed, but
  **it changes behaviour for any caller that did not set it**: the next plan
  shows the instance gaining a standby, and the bill roughly doubles.

  Callers that want a single-AZ instance must now say so. Task 1's staging
  workspace already did.

## v1.0.0

First tagged release. Ten modules, each in one place, consumed by git URL.

| Module | What it is |
|---|---|
| `security-group` | Every rule its own resource, addressed by name |
| `kms-key` | Customer-managed key, rotation on, readable key policy |
| `vpc` | Subnets, NAT, optional flow logs and VPC endpoints |
| `ec2` | Encrypted storage, IMDSv2 required, private by default |
| `rds` | Private, encrypted, enhanced monitoring |
| `iam-instance-role` | Scoped to one bucket, one prefix, one key |
| `cloudtrail` | Multi-region, validated, to S3 and CloudWatch Logs |
| `aws-config` | Recorder, delivery channel, twenty managed rules |
| `security-alerting` | Metric filters and alarms on the trail |
| `secret` | Generated credential in Secrets Manager |

Supersedes the per-task module directories. `task1/modules/vpc` and
`task2/modules/network` merged into `vpc`; `task1/modules/ec2` and
`task2/modules/compute` merged into `ec2`.
