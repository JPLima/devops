# A VPC with public and private subnets across several availability zones.
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

  #checkov:skip=CKV_AWS_130: This is the public subnet. Instances here are internet-facing by design; anything stateful belongs in the private subnets below.
  map_public_ip_on_launch = true

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
