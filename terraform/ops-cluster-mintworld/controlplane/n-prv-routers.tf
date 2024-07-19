locals {
  prv_routers_instance_type = data.aws_ec2_instance_type.instance_type_prv_routers.id
  prv_routers_count_min     = 3
  prv_routers_count_max     = 5

  // WARNING: This key is used in scripts.
  tailscale_role_tag = "prv-routers"
  // WARNING: This key is used in scripts.
}

resource "tailscale_tailnet_key" "tailscale_auth_key" {
  reusable            = true
  ephemeral           = true
  preauthorized       = true
  expiry              = 604800 // 7 days, an ideal time to rotate the AMI
  description         = "Auto-Generated Auth Key Subnet Router"
  recreate_if_invalid = "always"
  tags                = ["tag:mintworld"]
}

data "aws_subnet" "selected_subnets" {
  count = length(concat(data.aws_subnets.subnets_prv.ids, data.aws_subnets.subnets_pub.ids))
  id    = concat(data.aws_subnets.subnets_prv.ids, data.aws_subnets.subnets_pub.ids)[count.index]
}

data "cloudinit_config" "prv_routers_cic" {
  gzip          = false
  base64_encode = false

  part {
    filename     = "cloudinit--cloud-config-01-common.yml"
    content_type = "text/cloud-config"
    content      = file("${path.module}/templates/cloud-config/01-common.yml")
  }

  part {
    filename     = "cloudinit--startup-01-common.sh"
    content_type = "text/x-shellscript"
    content      = file("${path.module}/templates/user-data/01-common.sh")
  }

  part {
    filename     = "cloudinit--startup-04-tailscale.sh"
    content_type = "text/x-shellscript"
    content = templatefile("${path.module}/templates/user-data/04-tailscale.sh.tftpl", {
      tf_tailscale_authkey          = tailscale_tailnet_key.tailscale_auth_key.key
      tf_tailscale_advertise_routes = join(",", [for s in data.aws_subnet.selected_subnets : s.cidr_block])
    })
  }

}

resource "aws_launch_template" "prv_routers_lt" {
  name                    = "${local.prefix}-prv-routers-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.prv_routers_instance_type
  disable_api_termination = false
  update_default_version  = true

  vpc_security_group_ids = data.aws_security_groups.sg_main.ids

  key_name  = data.aws_key_pair.ssh_service_user_key.key_name
  user_data = base64gzip(data.cloudinit_config.prv_routers_cic.rendered)

  iam_instance_profile {
    name = data.aws_iam_instance_profile.instance_profile.name
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.stack_tags,
      {
        Role = local.tailscale_role_tag
      }
    )
  }

  metadata_options {
    instance_metadata_tags = "enabled"
    http_endpoint          = "enabled"
    http_tokens            = "required"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-prv-routers-lt"
      Role = local.tailscale_role_tag,
    }
  )
}

resource "aws_autoscaling_group" "prv_routers_asg" {

  launch_template {
    id      = aws_launch_template.prv_routers_lt.id
    version = aws_launch_template.prv_routers_lt.latest_version
  }

  name                      = "${local.prefix}-prv-routers-asg"
  max_size                  = local.prv_routers_count_max
  min_size                  = local.prv_routers_count_min
  desired_capacity          = local.prv_routers_count_min
  health_check_grace_period = 180
  health_check_type         = "EC2"
  vpc_zone_identifier       = data.aws_subnets.subnets_prv.ids
  wait_for_capacity_timeout = "10m"
  termination_policies      = ["OldestInstance"]

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 70 // 2/3 of instances must be healthy
    }
  }

}
