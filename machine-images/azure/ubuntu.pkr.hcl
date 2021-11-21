packer {
  required_plugins {
    azure = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/azure"
    }
  }
}

variable "az_sp_client_id" {
  default   = "${env("AZURE_SERVICE_PRINCIPAL_CLIENT_ID")}"
  sensitive = true

  validation {
    condition     = length(var.az_sp_client_id) > 0
    error_message = "The environment variable AZURE_SERVICE_PRINCIPAL_CLIENT_ID is not set."
  }
}

variable "az_sp_client_secret" {
  default   = "${env("AZURE_SERVICE_PRINCIPAL_CLIENT_SECRET")}"
  sensitive = true

  validation {
    condition     = length(var.az_sp_client_secret) > 0
    error_message = "The environment variable AZURE_SERVICE_PRINCIPAL_CLIENT_SECRET is not set."
  }
}

variable "az_sp_tenant_id" {
  default   = "${env("AZURE_SERVICE_PRINCIPAL_TENANT_ID")}"
  sensitive = true

  validation {
    condition     = length(var.az_sp_tenant_id) > 0
    error_message = "The environment variable AZURE_SERVICE_PRINCIPAL_TENANT_ID is not set."
  }
}

variable "az_subscription_id" {
  default   = "${env("AZURE_SUBSCRIPTION_ID")}"
  sensitive = true

  validation {
    condition     = length(var.az_subscription_id) > 0
    error_message = "The environment variable AZURE_SUBSCRIPTION_ID is not set."
  }
}

variable "image_offer" { default = "UbuntuServer" }
variable "image_publisher" { default = "Canonical" }
variable "image_sku" { default = "18.04-LTS" }
variable "location" { default = "eastus" }
variable "os_type" { default = "Linux" }
variable "resource_group" { default = "ops_rg_azure_machine_images" }
variable "vm_size" { default = "Standard_B2s" }
variable "ssh_username" { default = "freecodecamp" }

# TODO: These should be configurable via environment variables.
variable "scripts_dir" { default = "machine-images/scripts" }
variable "configs_dir" { default = "machine-images/configs" }

locals {
  name_prefix = "Ubuntu"
  name_suffix = "${formatdate("YYMMDD-hhmm", timestamp())}"
}

source "azure-arm" "ubuntu" {

  async_resourcegroup_delete = true

  subscription_id = var.az_subscription_id
  tenant_id       = var.az_sp_tenant_id
  client_secret   = var.az_sp_client_secret
  client_id       = var.az_sp_client_id

  image_offer     = var.image_offer
  image_publisher = var.image_publisher
  image_sku       = var.image_sku

  location = var.location
  os_type  = var.os_type

  managed_image_name                = "${local.name_prefix}-${var.image_sku}-${local.name_suffix}"
  managed_image_resource_group_name = var.resource_group

  vm_size      = var.vm_size
  ssh_username = var.ssh_username
}

build {
  name    = "ubuntu"
  sources = ["source.azure-arm.ubuntu"]

  provisioner "shell" {
    environment_vars = [
      "SSH_PROVISIONED_USER=${var.ssh_username}"
    ]
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    pause_before    = "60s"
    scripts = [
      "${var.scripts_dir}/install-dependencies.sh",
      "${var.scripts_dir}/install-golang.sh",
      "${var.scripts_dir}/install-docker.sh",
      "${var.scripts_dir}/install-docker-compose.sh",
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
