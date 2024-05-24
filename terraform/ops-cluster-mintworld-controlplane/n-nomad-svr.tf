locals {
  nomad_svr_instance_type = data.aws_ec2_instance_type.instance_type.id
  nomad_svr_count_min     = 3
  nomad_svr_count_max     = 5
  datacenter_name         = "mintworld"

  // WARNING: This key is used in scripts.
  nomad_role_tag = "nomad-svr"
  // WARNING: This key is used in scripts.
}

data "cloudinit_config" "nomad_svr_cic" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"
    content = templatefile("${path.module}/templates/cloudinit--cloud-config.yaml.tftpl", {

      tf__content_nomad_hcl = base64encode(templatefile("${path.module}/templates/nomad/server/nomad.hcl.tftpl", {
        tf_datacenter_name        = local.datacenter_name
        tf_nomad_bootstrap_expect = local.nomad_svr_count_min
        tf_aws_region             = var.region
        tf_nomad_join_tag_key     = "NomadCloudAutoJoinKey"
        tf_nomad_join_tag_value   = var.nomad_cloud_auto_join_key
      }))

      tf__content_nomad_service = filebase64("${path.module}/templates/nomad/server/nomad.service")

    })
  }

  part {
    filename     = "startup.sh"
    content_type = "text/x-shellscript"
    content      = file("${path.module}/templates/cloudinit--startup.sh")
  }

}

resource "aws_launch_template" "nomad_svr_lt" {
  name                    = "${local.prefix}-nomad-svr-lt"
  image_id                = data.hcp_packer_artifact.aws_ami.external_identifier
  instance_type           = local.nomad_svr_instance_type
  disable_api_termination = false
  key_name                = data.aws_key_pair.ssh_service_user_key.key_name

  iam_instance_profile {
    name = data.aws_iam_instance_profile.instance_profile.name
  }

  user_data = data.cloudinit_config.nomad_svr_cic.rendered

  tag_specifications {
    resource_type = "instance"
    tags = merge(
      var.stack_tags,
      {
        Role                  = local.nomad_role_tag
        NomadCloudAutoJoinKey = var.nomad_cloud_auto_join_key
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

  update_default_version = "true"

  tags = merge(
    var.stack_tags,
    {
      Name = "${local.prefix}-nomad-svr-lt"
      Role = local.nomad_role_tag,
    }
  )
}

resource "aws_autoscaling_group" "nomad_svr_asg" {

  launch_template {
    id      = aws_launch_template.nomad_svr_lt.id
    version = aws_launch_template.nomad_svr_lt.latest_version
  }

  name                      = "${local.prefix}-nomad-svr-asg"
  max_size                  = local.nomad_svr_count_max
  min_size                  = local.nomad_svr_count_min
  desired_capacity          = local.nomad_svr_count_min
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

  timeouts {
    update = "10m"
    delete = "10m"
  }
}
