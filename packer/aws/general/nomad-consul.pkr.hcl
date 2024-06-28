packer {
  required_version = "~> 1.10"
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    ansible = {
      version = "~> 1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

// Skip creating the AMI, useful for testing
variable "skip_create_ami" {
  description = "Skip creating the AMI, useful for testing"
  type        = bool
  default     = false
}

// The AWS configuration for the build
variable "aws_instance_type" {
  description = "The instance type to use for the build, from the AWS instance types list."
  type        = string
  default     = "t3a.medium"
}
variable "aws_region" {
  description = "The AWS region to use for the build, from the AWS regions list."
  type        = string
  default     = "us-east-1"
}
variable "root_volume_size_gb" {
  description = "The size of the root volume in GB"
  type        = number
  default     = 10
}
variable "ebs_delete_on_termination" {
  description = "Indicates whether the EBS volume is deleted on instance termination."
  type        = bool
  default     = true
}
variable "shutdown_behavior" {
  description = "The behavior when the instance is stopped."
  type        = string
  default     = "terminate"
}
variable "force_deregister" {
  description = "Indicates whether to force deregister the AMI."
  type        = bool
  default     = true
}
variable "force_delete_snapshot" {
  description = "Indicates whether to force delete the snapshot."
  type        = bool
  default     = true
}

// Nomad and Consul versions
variable "nomad_version" {
  description = "The version of Nomad to install."
  type        = string
  default     = "1.7.6"
}

variable "consul_version" {
  description = "The version of Consul to install."
  type        = string
  default     = "1.18.1"
}

// The SSH configuration for the build
variable "ssh_username" {
  description = "The username to use for SSH connections to the instance. Recommended: 'ubuntu' for Ubuntu AMIs, 'ec2-user' for Amazon Linux AMIs."
  type        = string
  default     = "ubuntu"
}

// The directory containing the scripts to run
variable "scripts_dir" {
  description = "The directory containing the scripts to run"
  type        = string
  default     = "aws/general/scripts"
}

// Parent Image
data "hcp-packer-version" "ubuntu" {
  bucket_name  = "aws-ubuntu"
  channel_name = "golden"
}
data "hcp-packer-artifact" "ubuntu" {
  bucket_name         = "aws-ubuntu"
  version_fingerprint = data.hcp-packer-version.ubuntu.fingerprint
  platform            = "aws"
  region              = var.aws_region
}

// The dynamic build configuration based on the variables
locals {
  image_version = "${formatdate("YYYYMMDD.hhmm", timestamp())}"

  image_description = "An Ubuntu Nomad Consul  - Server image with Docker installed."

  ansible_env_vars = [
    "ANSIBLE_HOST_KEY_CHECKING=False",
    "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3",
    "ANSIBLE_STDOUT_CALLBACK=yaml"
  ]
  ansible_extra_args = [
    "-v"
  ]
}

// The source AMI for the build
source "amazon-ebs" "nomad-consul" {
  skip_create_ami = var.skip_create_ami

  instance_type   = var.aws_instance_type
  region          = var.aws_region
  source_ami      = data.hcp-packer-artifact.ubuntu.external_identifier
  ami_name        = "ami-nomad-consul-${local.image_version}"
  ami_description = local.image_description

  shutdown_behavior     = var.shutdown_behavior
  force_deregister      = var.force_deregister
  force_delete_snapshot = var.force_delete_snapshot

  ssh_username = var.ssh_username

  tags = {
    "Base_AMI_Name" = data.hcp-packer-artifact.ubuntu.external_identifier,
    "Name"          = "Ubuntu-NomadConsul-${local.image_version}",
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = var.ebs_delete_on_termination
  }
}

// The build configuration
build {
  sources = [
    "source.amazon-ebs.nomad-consul"
  ]

  provisioner "shell" {
    inline = ["sleep 30"] // Wait for the instance to be ready
  }

  provisioner "ansible" {
    playbook_file    = "${var.scripts_dir}/ansible/install-nomad.yml"
    user             = var.ssh_username
    use_proxy        = false
    ansible_env_vars = local.ansible_env_vars
    extra_arguments = concat(
      local.ansible_extra_args,
      [
        "-e", "nomad_version=${var.nomad_version}"
      ]
    )
  }

  provisioner "ansible" {
    playbook_file    = "${var.scripts_dir}/ansible/install-consul.yml"
    user             = var.ssh_username
    use_proxy        = false
    ansible_env_vars = local.ansible_env_vars
    extra_arguments = concat(
      local.ansible_extra_args,
      [
        "-e", "consul_version=${var.consul_version}"
      ]
    )
  }

  hcp_packer_registry {
    bucket_name = "aws-nomad-consul"

    description = <<EOT
local.image_description
    EOT

    bucket_labels = {
      "aws_instance_type" = var.aws_instance_type
      "aws_region"        = var.aws_region
    }

    build_labels = {
      "os_base_image" = "{{ .SourceAMI }}"
    }
  }
}
