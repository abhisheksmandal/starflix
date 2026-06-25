# ── VPC ────────────────────────────────────────────────────────────────────────

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

# ── Internet Gateway ───────────────────────────────────────────────────────────

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# ── Public Subnets ─────────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-pub-${substr(var.azs[count.index], -2, 2)}"
    Tier = "public"
  })
}

# ── Private Subnets ────────────────────────────────────────────────────────────

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-priv-${substr(var.azs[count.index], -2, 2)}"
    Tier = "private"
  })
}

# ── Elastic IPs ────────────────────────────────────────────────────────────────
# One EIP per NAT Gateway. Count is 1 when single_nat_gateway = true,
# otherwise one per AZ.

locals {
  nat_count = var.single_nat_gateway ? 1 : length(var.public_subnet_cidrs)
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = local.nat_count == 1 ? "${var.name_prefix}-nat-eip" : "${var.name_prefix}-nat-eip-${substr(var.azs[count.index], -2, 2)}"
  })

  # EIPs that depend on an IGW must wait for it to be attached to the VPC.
  depends_on = [aws_internet_gateway.this]
}

# ── NAT Gateways ───────────────────────────────────────────────────────────────
# Placed in public subnets so they can route outbound traffic through the IGW.

resource "aws_nat_gateway" "this" {
  count = local.nat_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = local.nat_count == 1 ? "${var.name_prefix}-nat" : "${var.name_prefix}-nat-${substr(var.azs[count.index], -2, 2)}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ── Public Route Table ─────────────────────────────────────────────────────────
# One shared route table for all public subnets: 0.0.0.0/0 → IGW.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Tables ───────────────────────────────────────────────────────
# One route table per NAT Gateway. When single_nat_gateway = true, one shared
# table points all private subnets at the single NAT. Otherwise each AZ's
# private subnet routes through its own NAT Gateway for AZ-level resilience.

resource "aws_route_table" "private" {
  count  = local.nat_count
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = local.nat_count == 1 ? "${var.name_prefix}-rt-private" : "${var.name_prefix}-rt-private-${substr(var.azs[count.index], -2, 2)}"
  })
}

resource "aws_route" "private_nat" {
  count = local.nat_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id = aws_subnet.private[count.index].id

  # single_nat_gateway: all private subnets share the index-0 route table.
  # multi-NAT: each AZ subnet maps to its own per-AZ route table.
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}
