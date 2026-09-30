# ec2

An EC2 instance with the defaults AWS does not give you: encrypted storage,
IMDSv2 required, no public address unless asked for, and an AMI resolved at
plan time rather than hardcoded.

## Usage

### A public web tier

```hcl
module "web" {
  source = "git::https://github.com/JPLima/devops.git//modules/ec2?ref=v1.1.0"

  name               = "myapp-web"
  subnet_id          = module.vpc.public_subnet_ids[0]
  security_group_ids = [module.web_sg.id]
  instance_type      = "t3.small"
  kms_key_arn        = module.data_key.arn

  # Off by default. A public address should be a decision.
  associate_public_ip_address = true

  tags = { Project = "myapp" }
}
```

### A private instance reached through SSM

```hcl
module "app" {
  source = "git::https://github.com/JPLima/devops.git//modules/ec2?ref=v1.1.0"

  name               = "myapp-app"
  subnet_id          = module.vpc.private_subnet_ids[0]
  security_group_ids = [module.app_sg.id]

  # The role that carries AmazonSSMManagedInstanceCore.
  iam_instance_profile = module.iam.instance_profile_name
  kms_key_arn          = module.data_key.arn

  tags = { Project = "myapp" }
}
```

Then:

```bash
aws ssm start-session --target "$(terraform output -raw instance_id)"
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for the instance and its volumes. |
| `subnet_id` | `string` | required | Subnet to launch in. |
| `security_group_ids` | `list(string)` | required | Groups to attach. Build them with the `security-group` module. |
| `instance_type` | `string` | `"t3.micro"` | Instance type. |
| `ami_id` | `string` | `null` | AMI to launch. Null resolves the latest Amazon Linux 2023 image. |
| `associate_public_ip_address` | `bool` | `false` | Give the instance a public IP. |
| `root_volume_size` | `number` | `20` | Root volume size in GiB. |
| `kms_key_arn` | `string` | `null` | Customer-managed key for the root volume. |
| `iam_instance_profile` | `string` | `null` | Instance profile to attach. |
| `user_data` | `string` | `null` | Cloud-init script. Changes replace the instance. |
| `detailed_monitoring` | `bool` | `true` | One-minute CloudWatch metrics instead of five. |
| `tags` | `map(string)` | `{}` | Tags applied to the instance and its volumes. |

## Outputs

| Name | Description |
|---|---|
| `instance_id` | Instance id. |
| `arn` | Instance ARN. |
| `public_ip` | Public IP, `null` when the instance has none. |
| `public_dns` | Public DNS name, empty when there is no public IP. |
| `private_ip` | Private IP inside the VPC. |
| `private_dns` | Private DNS name inside the VPC. |
| `ami_id` | AMI the instance was launched from. |
| `availability_zone` | Zone the instance landed in. |

## Notes

**This module does not create a security group.** One caller needs a group
allowing HTTPS from named networks; another needs one with no ingress at all.
A flag would mean a module that sometimes owns a group and sometimes does not,
with outputs that are sometimes null. Compose `security-group` and pass the ids
in: one way to do it instead of two, and the group can then outlive any
particular instance.

**`ignore_changes = [ami]`.** The AMI data source returns a newer id whenever
Amazon publishes one. Without this, an unrelated apply would replace a running
instance. Replace deliberately, by tainting or by setting `ami_id`.

**IMDSv2 is required, with a hop limit of 1.** Version 1 answers an
unauthenticated `GET`, which is how a server-side request forgery bug in an
application turns into leaked role credentials. The hop limit stops a container
on the host from reaching the metadata service through the bridge.

**There is no `key_name`.** Access is Session Manager, so there is no key pair
to distribute, rotate or leak, and every session is a CloudTrail event rather
than a line in `sshd` logs. That needs an instance profile carrying
`AmazonSSMManagedInstanceCore` and, for a private instance, the three SSM
interface endpoints from the `vpc` module.

**The root volume is always encrypted.** With `kms_key_arn` it uses your key;
without, the AWS-managed EBS key. There is no way to turn encryption off.
