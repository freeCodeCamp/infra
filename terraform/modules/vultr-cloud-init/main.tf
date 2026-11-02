locals {
  cloud_config = {
    preserve_hostname = false
    hostname          = var.hostname
    users = [
      {
        name                = "freecodecamp"
        ssh_authorized_keys = var.ssh_authorized_keys
      },
    ]
  }
}
