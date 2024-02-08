resource "aws_vpc" "stg_mintworld_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-vpc"
    },
  )
}

resource "aws_internet_gateway" "stg_mintworld_igw" {
  vpc_id = aws_vpc.stg_mintworld_vpc.id

  tags = {
    Name = "stg-mintworld-igw"
  }
}

resource "aws_subnet" "stg_mintworld_subnet" {
  count             = length(local.subnet_base_ips)
  vpc_id            = aws_vpc.stg_mintworld_vpc.id
  availability_zone = data.aws_availability_zones.available.names[count.index % length(data.aws_availability_zones.available.names)]
  cidr_block        = "${local.subnet_base_ips[count.index]}/18"

  map_public_ip_on_launch = false

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-subnet-${count.index + 1}"
    },
  )
}

resource "aws_default_route_table" "stg_mintworld_default_rtb" {
  default_route_table_id = aws_vpc.stg_mintworld_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.stg_mintworld_igw.id
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-default-rtb"
    },
  )
}

resource "aws_default_security_group" "stg_mintworld_default_sg" {
  vpc_id = aws_vpc.stg_mintworld_vpc.id

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-default-sg"
    },
  )
}

resource "aws_security_group_rule" "stg_mintworld_sg_ingress_ssh" {
  security_group_id = aws_default_security_group.stg_mintworld_default_sg.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "stg_mintworld_sg_ingress_all_internal" {
  security_group_id = aws_default_security_group.stg_mintworld_default_sg.id
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [aws_vpc.stg_mintworld_vpc.cidr_block]
}
resource "aws_security_group_rule" "stg_mintworld_sg_egress_all" {
  security_group_id = aws_default_security_group.stg_mintworld_default_sg.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
