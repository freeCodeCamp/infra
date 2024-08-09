data "cloudinit_config" "consul_svr_cic" {
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
      tf__content_consul_hcl = base64encode(templatefile("${path.module}/templates/consul/server/consul.hcl.tftpl", {
        tf_datacenter              = local.datacenter
        tf_consul_bootstrap_expect = local.consul_svr_count_min
        tf_aws_region              = var.region
        tf_consul_join_tag_key     = "ConsulCloudAutoJoinKey"
        tf_consul_join_tag_value   = local.consul_cloud_auto_join_key
      }))
      tf__content_consul_service = filebase64("${path.module}/templates/consul/server/consul.service")
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
      tf_is_server  = "true"
    })
  }

}

resource "aws_launch_template" "consul_svr_lt" {
  name                    = "${local.prefix}-${local.infix_consul}-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.consul_svr_instance_type
  disable_api_termination = false
  update_default_version  = true

  vpc_security_group_ids = data.aws_security_groups.sg_main.ids

  key_name  = data.aws_key_pair.ssh_service_user_key.key_name
  user_data = base64gzip(data.cloudinit_config.consul_svr_cic.rendered)

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      delete_on_termination = true
    }
  }

  iam_instance_profile {
    name = data.aws_iam_instance_profile.instance_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.stack_tags,
      {
        Role = local.aws_tag__role_consul

        // WARNING: This key is used in scripts.
        ConsulCloudAutoJoinKey = local.consul_cloud_auto_join_key
        // WARNING: This key is used in scripts.
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
      Name = "${local.prefix}-${local.infix_consul}-lt"
      Role = local.aws_tag__role_consul
    }
  )
}

resource "aws_autoscaling_group" "consul_svr_asg" {

  launch_template {
    id      = aws_launch_template.consul_svr_lt.id
    version = aws_launch_template.consul_svr_lt.latest_version
  }

  name                      = "${local.prefix}-${local.infix_consul}-asg"
  max_size                  = local.consul_svr_count_max
  min_size                  = local.consul_svr_count_min
  desired_capacity          = local.consul_svr_count_min
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
}

resource "aws_cloudwatch_metric_alarm" "consul_svr_cma" {
  alarm_name          = "${local.prefix}-${local.infix_consul}-cma"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = local.consul_svr_count_min
  alarm_description   = "This metric monitors the number of healthy Consul servers"

  dimensions = {
    TargetGroup  = aws_lb_target_group.consul_svr_tg_8500.arn_suffix
    LoadBalancer = data.aws_lb.internal_lb.arn_suffix
  }

  alarm_actions = [aws_autoscaling_policy.consul_svr_scale_up.arn]
  ok_actions    = [aws_autoscaling_policy.consul_svr_scale_down.arn]
}

resource "aws_autoscaling_policy" "consul_svr_scale_up" {
  name                   = "${local.prefix}-${local.infix_consul}-scale-up"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.consul_svr_asg.name
}

resource "aws_autoscaling_policy" "consul_svr_scale_down" {
  name                   = "${local.prefix}-${local.infix_consul}-scale-down"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.consul_svr_asg.name
}

resource "aws_autoscaling_lifecycle_hook" "consul_svr_lc_hook" {
  name                   = "${local.prefix}-${local.infix_consul}-lc-hook"
  autoscaling_group_name = aws_autoscaling_group.consul_svr_asg.name
  default_result         = "CONTINUE"
  heartbeat_timeout      = 300
  lifecycle_transition   = "autoscaling:EC2_INSTANCE_TERMINATING"
}

resource "aws_lb_target_group" "consul_svr_tg_8500" {
  name     = "${local.prefix}-${local.infix_consul}-tg-8500"
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
      Name = "${local.prefix}-${local.infix_consul}-tg-8500"
    }
  )
}

resource "aws_lb_listener" "consul_svr_lblistner_8500" {
  load_balancer_arn = data.aws_lb.internal_lb.arn
  port              = "8500"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.consul_svr_tg_8500.arn
  }

  tags = merge(
    var.stack_tags, {
      Name = "${local.prefix}-${local.infix_consul}-lblistner-8500"
    }
  )
}

resource "aws_autoscaling_attachment" "consul_svr_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.consul_svr_asg.name
  lb_target_group_arn    = aws_lb_target_group.consul_svr_tg_8500.arn
}
