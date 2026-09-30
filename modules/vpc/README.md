# vpc

A VPC with public and private subnets across several availability zones, with
flow logs and VPC endpoints as options.

One module serves both an internet-facing web tier and a fully private
workload. What separates them is configuration, not a second copy of the code.

## Usage

### A public web tier

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.1.0"

  name       = "myapp-production"
  cidr_block = "10.20.0.0/16"
  az_count   = 3

  # Instances in the public subnets get a public IP. Off by default.
  map_public_ip_on_launch = true

  tags = { Project = "myapp" }
}
```

### A private workload reached through SSM

```hcl
module "vpc" {
  source = "git::https://github.com/JPLima/devops.git//modules/vpc?ref=v1.1.0"

  name       = "myapp-secure"
  cidr_block = "10.30.0.0/16"

  # The public subnets hold the NAT gateways and nothing else.
  map_public_ip_on_launch = false

  enable_flow_logs      = true
  flow_logs_kms_key_arn = module.observability_key.arn

  # What lets a private instance be managed without a route to the internet.
  interface_endpoints        = ["ssm", "ssmmessages", "ec2messages"]
  enable_s3_gateway_endpoint = true

  tags = { Project = "myapp" }
}
```

### A cheap non-production environment

```hcl
single_nat_gateway = true   # one NAT instead of one per AZ
az_count           = 2
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Name prefix for every resource. |
| `cidr_block` | `string` | required | CIDR block for the VPC. |
| `az_count` | `number` | `2` | Zones to spread subnets across. Two is the minimum for an RDS subnet group. |
| `subnet_newbits` | `number` | `8` | Bits added to the VPC prefix to size each subnet. With a `/16`, 8 gives `/24`s. |
| `map_public_ip_on_launch` | `bool` | `false` | Whether public subnets hand out public IPs. |
| `enable_nat_gateway` | `bool` | `true` | Create NAT gateways so private subnets reach the internet. |
| `single_nat_gateway` | `bool` | `false` | One shared NAT instead of one per AZ. |
| `enable_flow_logs` | `bool` | `false` | Record VPC Flow Logs to CloudWatch Logs. |
| `flow_logs_kms_key_arn` | `string` | `null` | Key encrypting the flow log group. Required when flow logs are on. |
| `flow_logs_retention_days` | `number` | `365` | Retention for the flow log group. |
| `flow_logs_traffic_type` | `string` | `"ALL"` | `ACCEPT`, `REJECT` or `ALL`. |
| `interface_endpoints` | `set(string)` | `[]` | Service names without the `com.amazonaws.<region>.` prefix. |
| `enable_s3_gateway_endpoint` | `bool` | `false` | Attach an S3 gateway endpoint to the private route tables. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC id. |
| `vpc_cidr_block` | CIDR block of the VPC. |
| `public_subnet_ids` | Public subnet ids, ordered by availability zone. |
| `private_subnet_ids` | Private subnet ids, ordered by availability zone. |
| `availability_zones` | Zones the subnets were placed in. |
| `nat_gateway_public_ips` | NAT public IPs, for allow-listing outbound traffic downstream. |
| `flow_log_group_name` | Log group receiving flow logs, `null` when disabled. |
| `flow_log_group_arn` | ARN of that log group, `null` when disabled. |
| `endpoints_security_group_id` | Group attached to the interface endpoints, `null` when there are none. |
| `interface_endpoint_ids` | Map of service name to endpoint id. |

## Notes

**Subnet CIDRs are computed, not listed.** `cidrsubnet` derives them from the
VPC CIDR. Public subnets take the low half of the address plan and private the
high half, so adding an availability zone never renumbers an existing subnet.

**Subnets are keyed by availability zone, not by index.** Removing a zone
destroys one subnet instead of shifting every index after it.

**`flow_logs_traffic_type` defaults to `ALL`, not `REJECT`.** Accepted traffic
is what tells you what an intruder reached; rejects only tell you what they
failed to reach.

**`ssmmessages` is not optional for Session Manager.** It carries the session
channel. Without it a session opens and then hangs, which is a confusing way to
spend an afternoon.

**The S3 endpoint is a gateway, not an interface.** Gateway endpoints attach to
route tables and are free; an interface endpoint for S3 bills per hour and per
gigabyte.

**Availability zones are filtered to `opt-in-not-required`.** Without that, a
Local Zone or Wavelength zone can appear in the list and a subnet lands
somewhere that does not support the services the workload needs.

**The endpoint security group comes from `../security-group`.** That relative
path is deliberate: when this module is fetched from a git tag, Terraform
resolves it inside the same fetched copy, so both modules are always the same
version.

## Cost

NAT gateways dominate. One costs roughly 30 USD a month plus data processing,
before any traffic. `single_nat_gateway = true` cuts that to one for the whole
VPC at the price of a single point of failure. Interface endpoints are about 7
USD a month each per availability zone.
