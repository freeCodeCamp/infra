locals {
  prefix               = "ops-mwnet"
  cloudflare_subdomain = "prv.mintworld"

  # Define the CIDR prefix ranges for subnets:
  # Needing 6 subnets, 3 private and 3 public,
  subnet_cidr_prefixes = cidrsubnets(
    "10.0.0.0/16",

    4, # "10.0.0.0/20" - Private Subnet - Availability Zone 1
    4, # "10.0.16.0/20" - Private Subnet - Availability Zone 2
    4, # "10.0.32.0/20" - Private Subnet - Availability Zone 3

    4, # "10.0.48.0/20" - Public Subnet - Availability Zone 1
    4, # "10.0.64.0/20" - Public Subnet - Availability Zone 2
    4  # "10.0.80.0/20" - Public Subnet - Availability Zone 3
  )

  stack_tags = merge(
    var.stack_tags,
    {
      Environment = "ops"
    }
  )
}

data "cloudflare_zone" "cf_zone" {
  name = "freecodecamp.net"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.stack_tags, { Name = "${local.prefix}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = merge(local.stack_tags, { Name = "${local.prefix}-igw" })
}

resource "aws_eip" "eip_nat" {
  count = length(slice(local.subnet_cidr_prefixes, 0, 3))

  domain = "vpc"

  tags = merge(local.stack_tags, {
    Name = "${local.prefix}-eip-nat-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }"
  })
}

resource "aws_default_route_table" "drt" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = merge(local.stack_tags, { Name = "${local.prefix}-drt" })
}

resource "aws_route_table" "rt_pub" {
  vpc_id = aws_vpc.vpc.id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(local.stack_tags, { Name = "${local.prefix}-rt-pub" })
}

resource "aws_subnet" "subnet_pub" {
  count = length(slice(local.subnet_cidr_prefixes, 3, 6))

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = element(local.subnet_cidr_prefixes, count.index + 3)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = var.enable_eip_on_launch_in_public_subnets
  ipv6_native             = false

  tags = merge(local.stack_tags, {
    Name = "${local.prefix}-subnet-pub-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
    Type = "Public"
  })
}

resource "aws_route_table_association" "rta_pub" {
  count = length(slice(local.subnet_cidr_prefixes, 3, 6))

  subnet_id      = element(aws_subnet.subnet_pub.*.id, count.index)
  route_table_id = aws_route_table.rt_pub.id
}

resource "aws_nat_gateway" "ngw" {
  count = length(slice(local.subnet_cidr_prefixes, 0, 3))

  allocation_id = element(aws_eip.eip_nat.*.id, count.index)
  subnet_id     = element(aws_subnet.subnet_pub.*.id, count.index)

  tags = merge(local.stack_tags, {
    Name = "${local.prefix}-ngw-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
  })

  depends_on = [
    aws_internet_gateway.igw,
    aws_eip.eip_nat
  ]
}

resource "aws_route_table" "rt_prv" {
  count = length(slice(local.subnet_cidr_prefixes, 0, 3))

  vpc_id = aws_vpc.vpc.id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.ngw.*.id, count.index)
  }

  tags = merge(local.stack_tags, {
    Name = "${local.prefix}-rt-prv-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }"
  })
}

resource "aws_subnet" "subnet_prv" {
  count = length(slice(local.subnet_cidr_prefixes, 0, 3))

  vpc_id            = aws_vpc.vpc.id
  cidr_block        = element(local.subnet_cidr_prefixes, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = false
  ipv6_native             = false

  tags = merge(local.stack_tags, {
    Name = "${local.prefix}-subnet-prv-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
    Type = "Private"
  })
}

resource "aws_route_table_association" "rta_prv" {
  count = length(slice(local.subnet_cidr_prefixes, 0, 3))

  subnet_id      = element(aws_subnet.subnet_prv.*.id, count.index)
  route_table_id = element(aws_route_table.rt_prv.*.id, count.index)
}

resource "aws_vpc_endpoint" "vpc_ep_s3" {
  vpc_id = aws_vpc.vpc.id

  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Gateway"
  private_dns_enabled = false

  route_table_ids = flatten([
    [aws_route_table.rt_pub.id],
    aws_route_table.rt_prv.*.id
  ])

  tags = merge(local.stack_tags, { Name = "${local.prefix}-vpc-ep-s3" })
}

# Add default security group for the VPC
resource "aws_default_security_group" "dsg" {
  vpc_id = aws_vpc.vpc.id

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.stack_tags, { Name = "${local.prefix}-dsg" })
}

resource "aws_security_group" "sg_main" {
  name        = "${local.prefix}-sg"
  description = "Primary security group for the VPC"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "Allow all inbound traffic within the VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Allow all outbound traffic to the internet
  egress {
    description      = "Allow all outbound traffic to the internet"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(local.stack_tags, { Name = "${local.prefix}-sg" })
}

resource "aws_lb" "internal_lb" {
  name               = "${local.prefix}-prv-lb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = [aws_security_group.sg_main.id]
  subnets            = aws_subnet.subnet_prv.*.id

  enable_cross_zone_load_balancing = true
  preserve_host_header             = true

  tags = merge(local.stack_tags, { Name = "${local.prefix}-prv-lb" })
}

resource "cloudflare_record" "internal_lb_dnsrecord" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "CNAME"
  proxied = false
  ttl     = 120

  name    = "${local.cloudflare_subdomain}.${data.cloudflare_zone.cf_zone.name}"
  content = aws_lb.internal_lb.dns_name
}

resource "cloudflare_record" "all__internal_lb_dnsrecord" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "CNAME"
  proxied = false
  ttl     = 120

  name    = "*.${local.cloudflare_subdomain}.${data.cloudflare_zone.cf_zone.name}"
  content = aws_lb.internal_lb.dns_name
}
