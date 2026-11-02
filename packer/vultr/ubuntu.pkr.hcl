packer {
  required_plugins {
    vultr = {
      source  = "github.com/vultr/vultr"
      version = "~> 2.7"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
      version = "~> 1.1"
    }
  }
}

locals {
  image_version = formatdate("YYYYMMDD.hhmm", timestamp())
  ansible_dir   = abspath("${path.root}/../../ansible")
  host_alias    = "img-ubuntu"
}

variable "vultr_api_key" {
  type      = string
  default   = env("VULTR_API_KEY")
  sensitive = true

  validation {
    condition     = length(var.vultr_api_key) > 0
    error_message = "The VULTR_API_KEY environment variable must be set or the -var vultr_api_key=xxxxx must be used to set the key value."
  }
}

variable "vultr_region" { default = "ewr" }
variable "vultr_plan" { default = "vc2-2c-4gb" }
variable "vultr_os_id" { default = 2760 }
variable "os_flavor" { default = "ubuntu" }
variable "os_version" { default = "26.04" }

source "vultr" "ubuntu" {
  api_key              = var.vultr_api_key
  os_id                = var.vultr_os_id
  plan_id              = var.vultr_plan
  region_id            = var.vultr_region
  instance_label       = "pkr-${var.os_flavor}-${var.os_version}-${local.image_version}"
  snapshot_description = "img-${var.os_flavor}-${var.os_version}-${local.image_version}"
  ssh_username         = "root"
  state_timeout        = "30m"
}

build {
  name    = "ubuntu"
  sources = ["source.vultr.ubuntu"]

  provisioner "ansible" {
    playbook_file = "${path.root}/image.yml"
    user          = "root"
    use_proxy     = false
    host_alias    = local.host_alias
    groups        = ["provider_vultr"]
    ansible_env_vars = [
      "ANSIBLE_CONFIG=${local.ansible_dir}/ansible.cfg",
      "ANSIBLE_HOST_PATTERN_MISMATCH=error"
    ]
    extra_arguments = [
      "-e", "@${local.ansible_dir}/inventory/group_vars/provider_vultr.yml",
      "-e", "variable_host=${local.host_alias}"
    ]
  }
}
