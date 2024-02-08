packer {
  required_plugins {
    aws = {
      version = "~> 1.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  image_version = "${formatdate("YYYYMMDD.hhmm", timestamp())}"
}

variable "source_ami_filter_name" {
  default = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "aws_instance_type" { default = "t3.medium" }
variable "aws_region" { default = "us-east-1" }
variable "aws_image_description" { default = "Ubuntu 22.04 LTS with Docker" }
variable "aws_os_version" { default = "22.04" }
variable "aws_os_flavor" { default = "ubuntu" }
variable "scripts_dir" { default = "aws/general/scripts" }

variable "root_volume_size_gb" {
  type    = number
  default = 10
}

variable "ebs_delete_on_termination" {
  description = "Indicates whether the EBS volume is deleted on instance termination."
  type        = bool
  default     = true
}

variable "global_tags" {
  description = "Tags to apply to everything"
  type        = map(string)
  default = {
    "Project" = "Ubuntu Docker AMI"
  }
}

variable "ami_tags" {
  description = "Tags to apply to the AMI"
  type        = map(string)
  default     = {}
}

variable "snapshot_tags" {
  description = "Tags to apply to the snapshot"
  type        = map(string)
  default     = {}
}

source "amazon-ebs" "ubuntu" {
  region = var.aws_region
  source_ami_filter {
    filters = {
      name                = var.source_ami_filter_name
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    owners      = ["099720109477"] // Canonical - Ubuntu Images
    most_recent = true
  }
  instance_type = var.aws_instance_type
  ssh_username  = "ubuntu"
  ami_name      = "AMI-${var.aws_os_flavor}-${var.aws_os_version}-${local.image_version}"

  tags = merge(
    var.global_tags,
    var.ami_tags,
    {
      "Name"          = "Ubuntu-Docker-${local.image_version}",
      "OS_Version"    = "ubuntu-${var.aws_os_version}",
      "Base_AMI_Name" = "{{ .SourceAMIName }}"
    }
  )
  snapshot_tags = merge(
    var.global_tags,
    var.snapshot_tags,
  )

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.root_volume_size_gb
    volume_type           = "gp3"
    delete_on_termination = var.ebs_delete_on_termination
  }
}

build {
  sources = [
    "source.amazon-ebs.ubuntu"
  ]

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/install-common.yml"
    user          = "ubuntu"
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3",
      "ANSIBLE_STDOUT_CALLBACK=yaml"
    ]
    extra_arguments = [
      "-v"
    ]
  }

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/reboot.yml"
    user          = "ubuntu"
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3",
      "ANSIBLE_STDOUT_CALLBACK=yaml"
    ]
    extra_arguments = [
      "-v"
    ]
  }

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/install-docker.yml"
    user          = "ubuntu"
    use_proxy     = false
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_PYTHON_INTERPRETER=/usr/bin/python3",
      "ANSIBLE_STDOUT_CALLBACK=yaml"
    ]
    extra_arguments = [
      "-v"
    ]
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
  }

  hcp_packer_registry {
    bucket_name = "aws-ubuntu"

    description = <<EOT
An Ubuntu 22.04 LTS - Server image with Docker installed.
    EOT

    bucket_labels = {
      "aws_instance_type" = var.aws_instance_type
      "aws_region"        = var.aws_region
      "aws_os_flavor"     = var.aws_os_flavor
      "aws_os_version"    = var.aws_os_version
    }

    build_labels = {
      "os_ami_id"     = "ami-${var.aws_os_flavor}-${var.aws_os_version}-${local.image_version}"
      "os_base_image" = "{{ .SourceAMI }}"
      "os_flavor"     = var.aws_os_flavor
      "os_version"    = var.aws_os_version
    }
  }
}
