data "cloudinit_config" "nomad_svr_cic" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloudinit--cloud-config-01-common.yml"
    content_type = "text/cloud-config"
    content      = file("${path.module}/templates/cloud-config/01-common.yml")
  }

  part {
    filename     = "cloudinit--cloud-config-02-consul.yml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-config/02-consul.yml.tftpl", {
      tf__content_consul_hcl = base64encode(templatefile("${path.module}/templates/consul/client/consul.hcl.tftpl", {
        tf_datacenter            = local.datacenter
        tf_aws_region            = var.region
        tf_consul_join_tag_key   = "ConsulCloudAutoJoinKey"
        tf_consul_join_tag_value = local.consul_cloud_auto_join_key
      }))
      tf__content_consul_service = filebase64("${path.module}/templates/consul/client/consul.service")
    })
  }

  part {
    filename     = "cloudinit--cloud-config-03-nomad.yml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-config/03-nomad.yml.tftpl", {
      tf__content_nomad_hcl = base64encode(templatefile("${path.module}/templates/nomad/server/nomad.hcl.tftpl", {
        tf_datacenter             = local.datacenter
        tf_nomad_bootstrap_expect = local.nomad_svr_count_min
        tf_consul_ui_url          = "http://prv.mintworld.freecodecamp.net:8500"
      }))
      tf__content_nomad_service = filebase64("${path.module}/templates/nomad/server/nomad.service")
    })
  }

  part {
    filename     = "cloudinit--startup-01-common.sh"
    content_type = "text/x-shellscript"
    content      = file("${path.module}/templates/user-data/01-common.sh")
  }

  part {
    filename     = "cloudinit--startup-02-consul.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/user-data/02-consul.sh.tftpl", {
      tf_datacenter = local.datacenter
      tf_is_server  = "false"
    })
  }

  part {
    filename     = "cloudinit--startup-03-nomad.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/user-data/03-nomad.sh.tftpl", {
      tf_datacenter = local.datacenter
    })
  }

}

resource "aws_launch_template" "nomad_svr_lt" {
  name                    = "${local.prefix}-${local.infix_nomad}-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.nomad_svr_instance_type
  disable_api_termination = false
  update_default_version  = true

  vpc_security_group_ids = data.aws_security_groups.sg_main.ids

  key_name  = data.aws_key_pair.ssh_service_user_key.key_name
  user_data = base64gzip(data.cloudinit_config.nomad_svr_cic.rendered)

  iam_instance_profile {
    name = data.aws_iam_instance_profile.instance_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.stack_tags,
      {
        Role = local.aws_tag__role_nomad
      }
    )
  }

  metadata_options {
    instance_metadata_tags = "enabled"
    http_endpoint          = "enabled"
    http_tokens            = "required"
  }

  monitoring {
    enabled = true
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-${local.infix_nomad}-lt"
      Role = local.aws_tag__role_nomad,
    }
  )
}

resource "aws_autoscaling_group" "nomad_svr_asg" {
  launch_template {
    id      = aws_launch_template.nomad_svr_lt.id
    version = aws_launch_template.nomad_svr_lt.latest_version
  }

  name                      = "${local.prefix}-${local.infix_nomad}-asg"
  max_size                  = local.nomad_svr_count_max
  min_size                  = local.nomad_svr_count_min
  desired_capacity          = local.nomad_svr_count_min
  health_check_type         = "ELB"
  health_check_grace_period = 300
  vpc_zone_identifier       = data.aws_subnets.subnets_prv.ids
  wait_for_capacity_timeout = "10m"
  termination_policies      = ["OldestInstance"]

  metrics_granularity = "1Minute"

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 66
      instance_warmup        = 180
    }
  }

  depends_on = [aws_autoscaling_group.consul_svr_asg]
}

resource "aws_cloudwatch_metric_alarm" "nomad_svr_cma" {
  alarm_name          = "${local.prefix}-${local.infix_nomad}-cma"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = local.nomad_svr_count_min
  alarm_description   = "This metric monitors the number of healthy Nomad servers"

  dimensions = {
    TargetGroup  = aws_lb_target_group.nomad_svr_tg_4646.arn_suffix
    LoadBalancer = data.aws_lb.internal_lb.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.nomad_svr_scale_up.arn]
  ok_actions    = [aws_autoscaling_policy.nomad_svr_scale_down.arn]
}

resource "aws_autoscaling_policy" "nomad_svr_scale_up" {
  name                   = "${local.prefix}-${local.infix_nomad}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nomad_svr_asg.name
}

resource "aws_autoscaling_policy" "nomad_svr_scale_down" {
  name                   = "${local.prefix}-${local.infix_nomad}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.nomad_svr_asg.name
}

resource "aws_autoscaling_lifecycle_hook" "nomad_svr_lc_hook" {
  name                   = "${local.prefix}-${local.infix_nomad}-lc-hook"
  autoscaling_group_name = aws_autoscaling_group.nomad_svr_asg.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}

resource "aws_lb_target_group" "nomad_svr_tg_4646" {
  name     = "${local.prefix}-${local.infix_nomad}-tg-4646"
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
      Name = "${local.prefix}-${local.infix_nomad}-tg-4646"
    }
  )
}

resource "aws_lb_listener" "nomad_svr_lblistner_4646" {
  load_balancer_arn = data.aws_lb.internal_lb.arn
  port              = "4646"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nomad_svr_tg_4646.arn
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-${local.infix_nomad}-lblistner-4646"
    }
  )
}

resource "aws_autoscaling_attachment" "nomad_svr_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.nomad_svr_asg.name
  lb_target_group_arn    = aws_lb_target_group.nomad_svr_tg_4646.arn
}
