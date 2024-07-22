resource "aws_lb" "internal_lb" {
  name               = "${local.prefix}-prv-lb"
  internal           = true
  load_balancer_type = "network"
  security_groups    = data.aws_security_groups.sg_main.ids
  subnets            = data.aws_subnets.subnets_prv.ids

  dns_record_client_routing_policy = "availability_zone_affinity"
}

resource "aws_lb_target_group" "tg_nomad_svr" {
  name     = "${local.prefix}-tg-nomad-svr"
  port     = 4646
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    path                = "/v1/agent/health"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-tg-nomad-svr"
    }
  )
}

resource "aws_lb_target_group" "tg_consul_svr" {
  name     = "${local.prefix}-tg-consul-svr"
  port     = 8500
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    path                = "/v1/agent/self"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-tg-consul-svr"
    }
  )
}

resource "aws_lb_listener" "listener_nomad_http" {
  load_balancer_arn = aws_lb.internal_lb.arn
  port              = "4646"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_nomad_svr.arn
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-nomad-http"
    }
  )
}

resource "aws_lb_listener" "listener_consul_http" {
  load_balancer_arn = aws_lb.internal_lb.arn
  port              = "8500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_consul_svr.arn
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-consul-http"
    }
  )
}

resource "aws_autoscaling_attachment" "nomad_svr_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.nomad_svr_asg.name
  lb_target_group_arn    = aws_lb_target_group.tg_nomad_svr.arn
}

resource "aws_autoscaling_attachment" "consul_svr_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.consul_svr_asg.name
  lb_target_group_arn    = aws_lb_target_group.tg_consul_svr.arn
}

resource "cloudflare_record" "internal_lb_dnsrecord" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "CNAME"
  proxied = false
  ttl     = 120

  name  = "${local.cloudflare_subdomain}.${data.cloudflare_zone.cf_zone.name}"
  value = aws_lb.internal_lb.dns_name
}
