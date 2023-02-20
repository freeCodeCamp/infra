packer {
  required_plugins {
    azure = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/azure" # From: https://github.com/hashicorp/packer-plugin-azure
    }
  }
}

variable "az_client_id" {
  default   = env("AZURE_CLIENT_ID")
  sensitive = true

  validation {
    condition     = length(var.az_client_id) > 0
    error_message = "The environment variable AZURE_CLIENT_ID is not set."
  }
}

variable "az_client_secret" {
  default   = env("AZURE_CLIENT_SECRET")
  sensitive = true

  validation {
    condition     = length(var.az_client_secret) > 0
    error_message = "The environment variable AZURE_CLIENT_SECRET is not set."
  }
}

variable "az_tenant_id" {
  default   = env("AZURE_TENANT_ID")
  sensitive = true

  validation {
    condition     = length(var.az_tenant_id) > 0
    error_message = "The environment variable AZURE_TENANT_ID is not set."
  }
}

variable "az_subscription_id" {
  default   = env("AZURE_SUBSCRIPTION_ID")
  sensitive = true

  validation {
    condition     = length(var.az_subscription_id) > 0
    error_message = "The environment variable AZURE_SUBSCRIPTION_ID is not set."
  }
}

variable "custom_managed_image_resource_group_name" { default = "ops-rg-machine-images" }
variable "custom_managed_image_name" {
  validation {
    condition     = length(var.custom_managed_image_name) > 0
    error_message = "The custom managed image name is not set. Please set the custom_managed_image_name variable."
  }
}

variable "artifact_image_type" { default = "Nomad" }
variable "location" { default = "eastus" }
variable "os_type" { default = "Linux" }
variable "resource_group" { default = "ops-rg-machine-images" }
variable "vm_size" { default = "Standard_B2s" }
variable "ssh_username" { default = "packer" } # This is the default username for provisioning and will be deleted after the build.

# TODO: These should be configurable via environment variables.
variable "scripts_dir" { default = "images/machines/scripts" }
variable "configs_dir" { default = "images/machines/configs" }

locals {
  artifact_name = "${var.artifact_image_type}-${var.location}-${formatdate("YYYYMMDD.hhmm", timestamp())}"
}

source "azure-arm" "nomad" {

  # AzureRM Parameters: https://www.packer.io/docs/builders/azure/arm
  async_resourcegroup_delete = true

  subscription_id = var.az_subscription_id
  tenant_id       = var.az_tenant_id
  client_secret   = var.az_client_secret
  client_id       = var.az_client_id

  custom_managed_image_name                = var.custom_managed_image_name
  custom_managed_image_resource_group_name = var.custom_managed_image_resource_group_name

  location = var.location
  os_type  = var.os_type

  managed_image_name                = local.artifact_name
  managed_image_resource_group_name = var.resource_group

  vm_size                 = var.vm_size
  ssh_username            = var.ssh_username
  temporary_key_pair_type = "ed25519"

  azure_tags = {
    "ops-created-by"   = "packer"
    "ops-image-type"   = var.artifact_image_type
    "ops-vm-size"      = var.vm_size
    "ops-vm-location"  = var.location
    "ops-image-source" = var.custom_managed_image_name
  }

}

build {
  name    = "nomad"
  sources = ["source.azure-arm.nomad"]

  # provisioner "file" {
  #   source      = "${var.configs_dir}/nomad"
  #   destination = "/tmp/"
  # }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    # Wait for OS updates, cloud-init etc. to be completed. This is arbitrary and works quite well.
    pause_before = "60s"
    scripts = [
      "${var.scripts_dir}/do-presetup.sh",
      "${var.scripts_dir}/installers/nomad.sh",
      "${var.scripts_dir}/do-cleanup.sh",
    ]
  }

  # Deprovision the Virtual Machine. This should be the last step in the build provisioners.
  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline = [
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
    inline_shebang = "/bin/sh -x"
  }

  post-processor "manifest" {
    output     = "manifest.json"
    strip_path = true
    custom_data = {
      source_image_name = "${build.SourceImageName}"
    }
  }

}
