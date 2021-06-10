source "azure-arm" "ubuntu" {
  client_id                         = "{{user `az_sp_client_id`}}"
  client_secret                     = "{{user `az_sp_client_secret`}}"
  image_offer                       = "UbuntuServer"
  image_publisher                   = "Canonical"
  image_sku                         = "18.04-LTS"
  location                          = "East US"
  managed_image_name                = "pxy-{{isotime \"060102-0304\" | clean_resource_name}}"
  managed_image_resource_group_name = "ops_rg"
  os_type                           = "Linux"
  subscription_id                   = "{{user `az_subscription_id`}}"
  tenant_id                         = "{{user `az_sp_tenant_id`}}"
  vm_size                           = "Standard_B2s"
}

build {
  sources = ["source.azure-arm.ubuntu"]

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} sudo -E sh '{{ .Path }}'"
    inline          = [
      "apt-get update",
      "apt-get upgrade -y",
      "apt-get -y install nginx",
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"
    ]
    inline_shebang  = "/bin/sh -x"
  }

}
