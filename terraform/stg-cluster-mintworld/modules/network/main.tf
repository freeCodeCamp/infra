data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "mw_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-vpc" })
}

resource "aws_internet_gateway" "mw_igw" {
  vpc_id = aws_vpc.mw_vpc.id

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-igw" })
}

resource "aws_eip" "mw_eip_nat" {
  count = length(slice(var.subnet_cidr_prefixes, 0, 3))

  domain = "vpc"

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-eip-nat-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }"
  })
}

resource "aws_default_route_table" "mw_drt" {
  default_route_table_id = aws_vpc.mw_vpc.default_route_table_id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-drt" })
}

resource "aws_route_table" "mw_rt_pub" {
  vpc_id = aws_vpc.mw_vpc.id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.mw_igw.id
  }

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-rt-pub" })
}

resource "aws_subnet" "mw_subnet_pub" {
  count = length(slice(var.subnet_cidr_prefixes, 3, 6))

  vpc_id            = aws_vpc.mw_vpc.id
  cidr_block        = element(var.subnet_cidr_prefixes, count.index + 3)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = var.enable_eip_on_launch_in_public_subnets
  ipv6_native             = false

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-subnet-pub-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
    Type = "Public"
  })
}

resource "aws_route_table_association" "mw_rta_pub" {
  count = length(slice(var.subnet_cidr_prefixes, 3, 6))

  subnet_id      = element(aws_subnet.mw_subnet_pub.*.id, count.index)
  route_table_id = aws_route_table.mw_rt_pub.id
}

resource "aws_nat_gateway" "mw_ngw" {
  count = length(slice(var.subnet_cidr_prefixes, 0, 3))

  allocation_id = element(aws_eip.mw_eip_nat.*.id, count.index)
  subnet_id     = element(aws_subnet.mw_subnet_pub.*.id, count.index)

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-ngw-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
  })

  depends_on = [
    aws_internet_gateway.mw_igw,
    aws_eip.mw_eip_nat
  ]
}

resource "aws_route_table" "mw_rt_prv" {
  count = length(slice(var.subnet_cidr_prefixes, 0, 3))

  vpc_id = aws_vpc.mw_vpc.id

  # Adopting the default route
  route {
    cidr_block = "10.0.0.0/16"
    gateway_id = "local"
  }

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = element(aws_nat_gateway.mw_ngw.*.id, count.index)
  }

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-rt-prv-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }"
  })
}

resource "aws_subnet" "mw_subnet_prv" {
  count = length(slice(var.subnet_cidr_prefixes, 0, 3))

  vpc_id            = aws_vpc.mw_vpc.id
  cidr_block        = element(var.subnet_cidr_prefixes, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  map_public_ip_on_launch = false
  ipv6_native             = false

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-subnet-prv-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }",
    Type = "Private"
  })
}

resource "aws_route_table_association" "mw_rta_prv" {
  count = length(slice(var.subnet_cidr_prefixes, 0, 3))

  subnet_id      = element(aws_subnet.mw_subnet_prv.*.id, count.index)
  route_table_id = element(aws_route_table.mw_rt_prv.*.id, count.index)
}

resource "aws_vpc_endpoint" "mw_vpc_ep_s3" {
  vpc_id = aws_vpc.mw_vpc.id

  service_name        = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type   = "Gateway"
  private_dns_enabled = false

  route_table_ids = flatten([
    [aws_route_table.mw_rt_pub.id],
    aws_route_table.mw_rt_prv.*.id
  ])

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-vpc-ep-s3" })
}

# Add default security group for the VPC
resource "aws_default_security_group" "mw_dsg" {
  vpc_id = aws_vpc.mw_vpc.id

  ingress {
    protocol  = -1
    self      = true
    from_port = 0
    to_port   = 0
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-dsg" })
}

resource "aws_security_group" "mw_sg" {
  name        = "${var.network_env}-mw-sg"
  description = "Security group for the Staging Mintworld VPC"
  vpc_id      = aws_vpc.mw_vpc.id

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

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-sg" })
}

resource "aws_security_group" "mw_sg_web" {
  name        = "${var.network_env}-mw-sg-web"
  description = "Security group for the Staging Mintworld VPC for Web Proxy"

  vpc_id = aws_vpc.mw_vpc.id

  ingress {
    description      = "Allow traffic from the internet to the Web Proxy"
    from_port        = 80
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  ingress {
    description      = "Allow traffic from the internet to the Web Proxy"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all outbound traffic to the internet"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_eip" "mw_eip_lb_web" {
  count = length(slice(var.subnet_cidr_prefixes, 3, 6))

  domain = "vpc"

  tags = merge(var.stack_tags, {
    Name = "${var.network_env}-mw-eip-lb-web-${
      replace(element(data.aws_availability_zones.available.names, count.index), "-", "")
    }"
  })
}

resource "aws_lb" "mw_lb_web" {
  name               = "${var.network_env}-mw-lb-web"
  internal           = false
  load_balancer_type = "network"

  security_groups = [
    aws_security_group.mw_sg_web.id
  ]

  dynamic "subnet_mapping" {
    for_each = aws_subnet.mw_subnet_pub
    content {
      subnet_id     = subnet_mapping.value.id
      allocation_id = aws_eip.mw_eip_lb_web[subnet_mapping.key].id
    }
  }

  tags = merge(var.stack_tags, { Name = "${var.network_env}-mw-lb-web" })
}
