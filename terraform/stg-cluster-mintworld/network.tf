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

resource "aws_lb" "stg_mintworld_nlb__consul" {
  name               = "stg-mintworld-nlb-consul"
  load_balancer_type = "network"
  internal           = false
  subnets            = aws_subnet.stg_mintworld_subnet[*].id

  # dynamic "subnet_mapping" {
  #   for_each = aws_subnet.stg_mintworld_subnet[*]
  #   content {
  #     subnet_id = subnet_mapping.value.id
  #     private_ipv4_address = cidrhost(
  #       "${subnet_mapping.value.cidr_block}",
  #       local.ip_start_nlb_consul + index(aws_subnet.stg_mintworld_subnet[*], subnet_mapping.value)
  #     )
  #   }
  # }

  security_groups = [
    aws_default_security_group.stg_mintworld_default_sg.id
  ]

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-nlb-consul"
    },
  )

}
resource "aws_lb" "stg_mintworld_nlb__nomad" {
  name               = "stg-mintworld-nlb-nomad"
  load_balancer_type = "network"
  internal           = false
  subnets            = aws_subnet.stg_mintworld_subnet[*].id

  # dynamic "subnet_mapping" {
  #   for_each = aws_subnet.stg_mintworld_subnet[*]
  #   content {
  #     subnet_id = subnet_mapping.value.id
  #     private_ipv4_address = cidrhost(
  #       "${subnet_mapping.value.cidr_block}",
  #       local.ip_start_nlb_nomad + index(aws_subnet.stg_mintworld_subnet[*], subnet_mapping.value)
  #     )
  #   }
  # }

  security_groups = [
    aws_default_security_group.stg_mintworld_default_sg.id
  ]

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-nlb-nomad"
    },
  )
}

resource "aws_lb_target_group" "stg_mintworld_tg__consul" {
  name     = "stg-mintworld-tg-consul"
  port     = 8500
  protocol = "TCP"
  vpc_id   = aws_vpc.stg_mintworld_vpc.id

  health_check {
    port     = 8500
    protocol = "TCP"
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-tg-consul"
    },
  )
}

resource "aws_lb_target_group" "stg_mintworld_tg__nomad" {
  name     = "stg-mintworld-tg-nomad"
  port     = 4646
  protocol = "TCP"
  vpc_id   = aws_vpc.stg_mintworld_vpc.id

  health_check {
    port     = 4646
    protocol = "TCP"
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mintworld-tg-nomad"
    },
  )

}

resource "aws_lb_listener" "stg_mintworld_listener__consul" {
  load_balancer_arn = aws_lb.stg_mintworld_nlb__consul.arn
  port              = 8500
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stg_mintworld_tg__consul.arn
  }

}

resource "aws_lb_listener" "stg_mintworld_listener__nomad" {
  load_balancer_arn = aws_lb.stg_mintworld_nlb__nomad.arn
  port              = 4646
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.stg_mintworld_tg__nomad.arn
  }

}

resource "cloudflare_record" "stg_mintworld_dns__consul" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "CNAME"
  proxied = false
  ttl     = 120

  value = aws_lb.stg_mintworld_nlb__consul.dns_name
  name  = "consul.mintworld.stg.${var.network_subdomain}"
}

resource "cloudflare_record" "stg_mintworld_dns__nomad" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "CNAME"
  proxied = false
  ttl     = 120

  value = aws_lb.stg_mintworld_nlb__nomad.dns_name
  name  = "nomad.mintworld.stg.${var.network_subdomain}"
}
