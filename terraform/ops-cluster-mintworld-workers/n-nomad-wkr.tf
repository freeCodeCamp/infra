locals {
  nomad_wkr_instance_type = data.aws_ec2_instance_type.instance_type.id
  nomad_wkr_count_min     = 5
  nomad_wkr_count_max     = 10

  // WARNING: This key is used in scripts.
  nomad_role_tag = "nomad-wkr"
  // WARNING: This key is used in scripts.
}

data "cloudinit_config" "nomad_wkr_cic" {
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
        tf_consul_join_tag_value = var.consul_cloud_auto_join_key
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
        tf_client_role = local.nomad_role_tag == "nomad-wkr" ? "worker" : "default"
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

resource "aws_launch_template" "nomad_wkr_lt" {
  name                    = "${local.prefix}-nomad-wkr-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.nomad_wkr_instance_type
  disable_api_termination = false
  key_name                = data.aws_key_pair.ssh_service_user_key.key_name

  iam_instance_profile {
    name = data.aws_iam_instance_profile.instance_profile.name
  }

  user_data = base64gzip(data.cloudinit_config.nomad_wkr_cic.rendered)

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.stack_tags,
      {
        Role = local.nomad_role_tag
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

  update_default_version = true

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-nomad-wkr-lt"
      Role = local.nomad_role_tag,
    }
  )
}

resource "aws_autoscaling_group" "nomad_wkr_asg" {

  launch_template {
    id      = aws_launch_template.nomad_wkr_lt.id
    version = aws_launch_template.nomad_wkr_lt.latest_version
  }

  name                      = "${local.prefix}-nomad-wkr-asg"
  max_size                  = local.nomad_wkr_count_max
  min_size                  = local.nomad_wkr_count_min
  desired_capacity          = local.nomad_wkr_count_min
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
