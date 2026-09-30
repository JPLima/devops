# Network for a workload that must not be reachable from the internet.
#
# Public subnets exist only to hold the NAT gateways. Nothing is launched in
# them. The private subnets reach AWS APIs through VPC endpoints rather than
# the NAT, so the traffic never leaves the AWS network.

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
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  public_subnet_cidrs = [
    for index in range(var.az_count) : cidrsubnet(var.cidr_block, 8, index)
  ]

  private_subnet_cidrs = [
    for index in range(var.az_count) : cidrsubnet(var.cidr_block, 8, index + var.az_count)
  ]
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

resource "aws_subnet" "public" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = local.public_subnet_cidrs[each.value]

  # Even here. These subnets hold NAT gateways, which get an Elastic IP
  # explicitly; nothing should acquire a public address by accident.
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = { for index, az in local.azs : az => index }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = local.private_subnet_cidrs[each.value]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  for_each = aws_subnet.public

  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = aws_subnet.public

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = each.value.id

  tags = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

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

resource "aws_route_table" "private" {
  for_each = aws_subnet.private

  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route" "private_nat" {
  for_each = aws_subnet.private

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

# ---------------------------------------------------------------------------
# VPC flow logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}

data "aws_iam_policy_document" "flow_logs_assume" {
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
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]

    # Scoped to this log group and its streams, not logs:* on *.
    resources = [
      aws_cloudwatch_log_group.flow_logs.arn,
      "${aws_cloudwatch_log_group.flow_logs.arn}:*",
    ]
  }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix        = "${var.name}-flow-logs-"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json

  tags = merge(var.tags, { Name = "${var.name}-flow-logs" })
}

resource "aws_iam_role_policy" "flow_logs" {
  name_prefix = "${var.name}-flow-logs-"
  role        = aws_iam_role.flow_logs.id
  policy      = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id = aws_vpc.this.id

  # ALL, not REJECT. Accepted traffic is what tells you what an intruder
  # reached; rejects only tell you what they failed to reach.
  traffic_type = "ALL"

  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

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

module "endpoints_sg" {
  source = "../../../modules/security-group"

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

locals {
  # The three interface endpoints Session Manager needs. ssmmessages carries
  # the session channel; without it a session opens and then hangs.
  interface_endpoints = toset(["ssm", "ssmmessages", "ec2messages"])
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for subnet in aws_subnet.private : subnet.id]
  security_group_ids  = [module.endpoints_sg.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name}-${each.key}" })
}

# Gateway endpoint rather than interface: S3 gateway endpoints are free and
# attach to route tables instead of costing per-hour and per-GB.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for table in aws_route_table.private : table.id]

  tags = merge(var.tags, { Name = "${var.name}-s3" })
}
