data "cloudinit_config" "nomad_web_cic" {
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
    filename     = "cloudinit--cloud-config-01-common.yml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloud-config/03-nomad.yml.tftpl", {
      tf__content_nomad_hcl = base64encode(templatefile("${path.module}/templates/nomad/client/nomad.hcl.tftpl", {
        tf_datacenter  = local.datacenter
        tf_client_role = local.cluster_tag__client_role
      }))
      tf__content_nomad_service = filebase64("${path.module}/templates/nomad/client/nomad.service")
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

resource "aws_launch_template" "nomad_web_lt" {
  name                    = "${local.prefix}-nomad-web-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.nomad_web_instance_type
  disable_api_termination = false
  update_default_version  = true

  vpc_security_group_ids = data.aws_security_groups.sg_main.ids

  key_name  = data.aws_key_pair.ssh_service_user_key.key_name
  user_data = base64gzip(data.cloudinit_config.nomad_web_cic.rendered)

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
      Name = "${local.prefix}-nomad-web-lt"
      Role = local.aws_tag__role_nomad,
    }
  )
}

resource "aws_autoscaling_group" "nomad_web_asg" {

  launch_template {
    id      = aws_launch_template.nomad_web_lt.id
    version = aws_launch_template.nomad_web_lt.latest_version
  }

  name                      = "${local.prefix}-nomad-web-asg"
  max_size                  = local.nomad_web_count_max
  min_size                  = local.nomad_web_count_min
  desired_capacity          = local.nomad_web_count_min
  health_check_grace_period = 180
  health_check_type         = "EC2"
  vpc_zone_identifier       = data.aws_subnets.subnets_prv.ids
  wait_for_capacity_timeout = "10m"
  termination_policies      = ["OldestInstance"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances"
  ]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 70 // 2/3 of instances must be healthy
    }
  }
}

resource "aws_lb_target_group" "tg_nomad_web" {
  name     = "${local.prefix}-tg-nomad-web"
  port     = 80
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    port                = 8082
    path                = "/ping"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-tg-nomad-web"
    }
  )
}

resource "aws_lb_listener" "listener_nomad_web" {
  load_balancer_arn = data.aws_lb.internal_lb.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_nomad_web.arn
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-nomad-web"
    }
  )
}

resource "aws_autoscaling_attachment" "nomad_web_asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.nomad_web_asg.name
  lb_target_group_arn    = aws_lb_target_group.tg_nomad_web.arn
}

resource "aws_lb_target_group" "tg_nomad_web_traefik" {
  name     = "${local.prefix}-tg-nomad-web-traefik"
  port     = 8081
  protocol = "TCP"
  vpc_id   = data.aws_vpc.vpc.id

  health_check {
    port                = 8082
    path                = "/ping"
    healthy_threshold   = 2
    unhealthy_threshold = 10
    timeout             = 5
    interval            = 10
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-tg-nomad-web-traefik"
    }
  )
}

resource "aws_lb_listener" "listener_nomad_web_traefik" {
  load_balancer_arn = data.aws_lb.internal_lb.arn
  port              = 8081
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg_nomad_web_traefik.arn
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-nomad-web-traefik"
    }
  )
}

resource "aws_autoscaling_attachment" "nomad_web_asg_attachment_traefik" {
  autoscaling_group_name = aws_autoscaling_group.nomad_web_asg.name
  lb_target_group_arn    = aws_lb_target_group.tg_nomad_web_traefik.arn
}
