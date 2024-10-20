packer {
  required_plugins {
    digitalocean = {
      version = ">= 1.4.0"
      source  = "github.com/digitalocean/digitalocean"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = ">= 1.1.0"
    }
  }
}

variable "scripts_dir" { default = "digitalocean/scripts" }

locals { image_version = "${formatdate("YYYYMMDD.hhmm", timestamp())}" }

variable "do_api_token" {
  type    = string
  default = env("DO_API_TOKEN")

  validation {
    condition     = length(var.do_api_token) > 0
    error_message = "The DO_API_TOKEN environment variable must be set or the -var do_api_token=xxxxx must be used to set the token value."
  }
}

variable "do_size" { default = "s-2vcpu-2gb" }
variable "do_region" { default = "nyc3" }
variable "do_image" { default = "ubuntu-24-04-x64" }
variable "do_image_description" { default = "Ubuntu 24.04 LTS" }
variable "do_os_version" { default = "24.04" }
variable "do_os_flavor" { default = "ubuntu" }

source "digitalocean" "ubuntu" {
  api_token    = "${var.do_api_token}"
  image        = var.do_image
  region       = var.do_region
  size         = var.do_size
  snapshot_name = "ami-${var.do_os_flavor}-${var.do_os_version}-${local.image_version}"
  ssh_username = "root"
}

build {
  name    = "ubuntu"
  sources = ["source.digitalocean.ubuntu"]

  provisioner "ansible" {
    playbook_file = "${var.scripts_dir}/ansible/install-common.yml"
    user          = "root"
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
    user          = "root"
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
    user          = "root"
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
    bucket_name = "digitalocean-ubuntu"

    description = <<EOT
An Ubuntu LTS - Server image with Docker installed.
    EOT

    bucket_labels = {
      "do_size"    = var.do_size
      "do_region"  = var.do_region
      "os_flavor"  = var.do_os_flavor
      "os_version" = var.do_os_version
    }

    build_labels = {
      "os_ami_id"     = "ami-${var.do_os_flavor}-${var.do_os_version}-${local.image_version}"
      "os_base_image" = var.do_image
      "os_flavor"     = var.do_os_flavor
      "os_version"    = var.do_os_version
    }
  }
}
