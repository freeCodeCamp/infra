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

// The OS configuration for the build
variable "aws_os_version" {
  description = "The OS version to use for the build. Example: '24.04'"
  type        = string
  default     = "24.04"
}
variable "aws_os_flavor" {
  description = "The OS flavor to use for the build. Example: 'ubuntu'"
  type        = string
  default     = "ubuntu"
}
variable "aws_os_arch" {
  description = "The OS architecture to use for the build. Example: 'x86_64' or 'arm64'"
  type        = string
  default     = "x86_64"
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

// The dynamic build configuration based on the variables
locals {
  image_version = "${formatdate("YYYYMMDD.hhmm", timestamp())}"

  // The source AMI filter name, based on the OS flavor, version, and architecture
  // Example: "ubuntu/images/*/ubuntu-*-24.04-*-server-*"
  source_ami_filter_name = "${var.aws_os_flavor}/images/*/${var.aws_os_flavor}-*-${var.aws_os_version}-*-server-*"

  image_description = "An ${var.aws_os_flavor} ${var.aws_os_version} ${var.aws_os_arch} - Server image with Docker installed."

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
source "amazon-ebs" "ubuntu" {
  source_ami_filter {
    filters = {
      architecture        = var.aws_os_arch
      name                = local.source_ami_filter_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    // owners      = ["099720109477"] // "Canonical - Ubuntu Images" is chargable ??
    owners      = ["amazon"]
    most_recent = true
  }

  skip_create_ami = var.skip_create_ami

  instance_type   = var.aws_instance_type
  region          = var.aws_region
  ami_name        = "ami-${var.aws_os_flavor}-${var.aws_os_version}-${var.aws_os_arch}-${local.image_version}"
  ami_description = local.image_description


  shutdown_behavior     = var.shutdown_behavior
  force_deregister      = var.force_deregister
  force_delete_snapshot = var.force_delete_snapshot

  ssh_username = var.ssh_username

  tags = {
    "Name"          = "Ubuntu-Docker-${local.image_version}",
    "OS_Version"    = var.aws_os_version,
    "OS_Flavor"     = var.aws_os_flavor,
    "OS_Arch"       = var.aws_os_arch,
    "Base_AMI_ID"   = "{{ .SourceAMI }}"
    "Base_AMI_Name" = "{{ .SourceAMIName }}"
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
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "shell" {
    inline = ["sleep 30"] // Wait for the instance to be ready
  }

  provisioner "ansible" {
    playbook_file    = "${var.scripts_dir}/ansible/install-common.yml"
    user             = var.ssh_username
    use_proxy        = false
    ansible_env_vars = local.ansible_env_vars
    extra_arguments  = local.ansible_extra_args
  }

  provisioner "ansible" {
    playbook_file    = "${var.scripts_dir}/ansible/install-docker.yml"
    user             = var.ssh_username
    use_proxy        = false
    ansible_env_vars = local.ansible_env_vars
    extra_arguments  = local.ansible_extra_args
  }

  provisioner "file" {
    source      = "${var.scripts_dir}/files/99_custom_cloud_init.cfg.tpl"
    destination = "/tmp/99_custom_cloud_init.cfg"
  }

  provisioner "shell" {
    inline = [
      "sudo mv /tmp/99_custom_cloud_init.cfg /etc/cloud/cloud.cfg.d/99_custom_cloud_init.cfg",
    ]
  }

  hcp_packer_registry {
    bucket_name = "aws-ubuntu"

    description = <<EOT
local.image_description
    EOT

    bucket_labels = {
      "aws_instance_type" = var.aws_instance_type
      "aws_region"        = var.aws_region
      "aws_os_flavor"     = var.aws_os_flavor
      "aws_os_version"    = var.aws_os_version
      "aws_os_arch"       = var.aws_os_arch
    }

    build_labels = {
      "os_ami_id"     = "ami-${var.aws_os_flavor}-${var.aws_os_version}-${var.aws_os_arch}-${local.image_version}"
      "os_base_image" = "{{ .SourceAMI }}"
      "os_flavor"     = var.aws_os_flavor
      "os_version"    = var.aws_os_version
      "os_arch"       = var.aws_os_arch
    }
  }
}
