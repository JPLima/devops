# A VPC with public and private subnets across several availability zones.
#
# One module serves both a public web tier and a fully private workload. What
# separates the two is configuration, not a second copy of this file:
#
#   public tier     map_public_ip_on_launch = true
#   private tier    interface_endpoints = ["ssm", "ssmmessages", "ec2messages"]
#                   enable_s3_gateway_endpoint = true
#                   enable_flow_logs = true
#
# Subnet CIDRs are derived from the VPC CIDR with cidrsubnet rather than passed
# in as a list. One variable changes the whole address plan, and the module
# works for any VPC size without the caller recalculating anything.

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394: Pinning zone ids would tie the module to one region. The opt-in filter below excludes Local Zones and Wavelength zones, which is the result-set expansion that actually matters, and slice() bounds the count.
  state = "available"

  # Standard zones only. Without this, a Local Zone or Wavelength zone can
  # appear in the list and a subnet lands somewhere that does not support the
  # services the workload needs.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

locals {
  # Take the first az_count zones that are actually available in the region,
  # rather than assuming a, b and c exist.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Public subnets take the low half of the address plan, private the high
  # half, so adding an AZ never renumbers an existing subnet.
  public_subnet_cidrs = [
    for index in range(var.az_count) :
    cidrsubnet(var.cidr_block, var.subnet_newbits, index)
  ]

  private_subnet_cidrs = [
    for index in range(var.az_count) :
    cidrsubnet(var.cidr_block, var.subnet_newbits, index + var.az_count)
  ]

  nat_gateway_count = var.enable_nat_gateway ? (var.single_nat_gateway ? 1 : var.az_count) : 0

  needs_endpoint_security_group = length(var.interface_endpoints) > 0
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = var.name })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

# Subnets are keyed by availability zone name rather than by index. Removing a
# zone from the middle of the list then destroys only that subnet, instead of
# shifting every index after it.
resource "aws_subnet" "public" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.public_subnet_cidrs[each.value]

  #checkov:skip=CKV_AWS_130: The caller decides. It defaults to false; a public web tier opts in explicitly.
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.private_subnet_cidrs[each.value]

  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = local.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[local.azs[count.index]].id

  tags = merge(var.tags, { Name = "${var.name}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet, so each can point at the NAT gateway in
# its own zone. With single_nat_gateway they all point at the same one.
resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = var.enable_nat_gateway ? aws_subnet.private : {}

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[index(local.azs, each.key)].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# ---------------------------------------------------------------------------
# Flow logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })

  lifecycle {
    precondition {
      condition     = var.flow_logs_kms_key_arn != null
      error_message = "flow_logs_kms_key_arn is required when enable_flow_logs is true. Flow logs carry source and destination addresses for every connection in the VPC."
    }
  }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    # Scoped to this log group and its streams, not logs:* on *.
    resources = [
      aws_cloudwatch_log_group.flow_logs[0].arn,
      "${aws_cloudwatch_log_group.flow_logs[0].arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix        = "${var.name}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume[0].json

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name_prefix = "${var.name}-flow-logs-"
  role        = aws_iam_role.flow_logs[0].id
  policy      = data.aws_iam_policy_document.flow_logs[0].json
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id       = aws_vpc.this.id
  traffic_type = var.flow_logs_traffic_type

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn         = aws_iam_role.flow_logs[0].arn

  max_aggregation_interval = 60

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}

# ---------------------------------------------------------------------------
# VPC endpoints
#
# These are what let a private instance be managed by SSM without a route to
# the internet. Without them the instance would need the NAT gateway just to
# reach the SSM control plane.
# ---------------------------------------------------------------------------

# Relative source on purpose. When this module is fetched from a git tag,
# Terraform resolves a relative source inside the same fetched copy, so the
# security-group module comes from the same version as this one. A git URL
# here would let the two drift apart.
module "endpoints_sg" {
  source = "../security-group"

  count = local.needs_endpoint_security_group ? 1 : 0

  name        = "${var.name}-vpc-endpoints"
  description = "Interface endpoints for ${var.name}"
  vpc_id      = aws_vpc.this.id

  ingress_rules = {
    "https-from-vpc" = {
      description = "HTTPS from inside the VPC"
      ip_protocol = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_ipv4   = aws_vpc.this.cidr_block
    }
  }

  egress_rules = {}

  tags = var.tags
}

resource "aws_vpc_endpoint" "interface" {
  for_each = var.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [module.endpoints_sg[0].id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

resource "aws_vpc_endpoint" "s3" {
  count = var.enable_s3_gateway_endpoint ? 1 : 0

  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for table in aws_route_table.private : table.id]

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}
