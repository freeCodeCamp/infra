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

variable "image_offer" { default = "0001-com-ubuntu-server-focal" }
variable "image_publisher" { default = "Canonical" }
variable "image_sku" { default = "20_04-LTS-gen2" }

variable "artifact_image_type" { default = "Ubuntu" }
variable "location" { default = "eastus" }
variable "os_type" { default = "Linux" }
variable "resource_group" { default = "ops-rg-machine-images" }
variable "vm_size" { default = "Standard_B2s" }
variable "ssh_username" { default = "packer" } # This is the default username for provisioning and will be deleted after the build.

# TODO: These should be configurable via environment variables.
variable "scripts_dir" { default = "azure/scripts" }

locals {
  artifact_name = "${var.artifact_image_type}-${var.image_sku}-${var.location}-${formatdate("YYYYMMDD.hhmm", timestamp())}"
}

source "azure-arm" "ubuntu" {

  # AzureRM Parameters: https://www.packer.io/docs/builders/azure/arm
  async_resourcegroup_delete = true

  subscription_id = var.az_subscription_id
  tenant_id       = var.az_tenant_id
  client_secret   = var.az_client_secret
  client_id       = var.az_client_id

  image_offer     = var.image_offer
  image_publisher = var.image_publisher
  image_sku       = var.image_sku

  location = var.location
  os_type  = var.os_type

  managed_image_name                = local.artifact_name
  managed_image_resource_group_name = var.resource_group

  vm_size      = var.vm_size
  ssh_username = var.ssh_username
  # temporary_key_pair_type = "ed25519"            # This is not yet supported by the Azure Builder Plugin. https://github.com/hashicorp/packer-plugin-azure/issues/201

  azure_tags = {
    "ops-created-by"    = "packer"
    "ops-image-type"    = var.artifact_image_type
    "ops-build-vm-size" = var.vm_size
    "ops-location"      = var.location
    "ops-image-source"  = var.image_sku
  }

}

build {
  name    = "ubuntu"
  sources = ["source.azure-arm.ubuntu"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    # Wait for OS updates, cloud-init etc. to be completed. This is arbitrary and works quite well.
    pause_before = "60s"
    scripts = [
      "${var.scripts_dir}/do-presetup.sh",
      "${var.scripts_dir}/installers/golang.sh",
      "${var.scripts_dir}/installers/docker.sh",
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
