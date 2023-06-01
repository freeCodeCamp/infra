resource "linode_instance" "ops_o11y_workers" {
  count     = var.worker_node_count
  image     = var.image_id
  label     = "ops-vm-o11y-wkr-${count.index + 1}"
  group     = "ops-o11y"
  region    = var.region
  type      = "g6-standard-2"
  root_pass = var.password

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = self.ip_address
  }

  provisioner "remote-exec" {
    inline = [
      # Update the system.
      "apt-get update -qq",
      # Disable password authentication; users can only connect with an SSH key.
      "sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config",
      "echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config",
      "apt-get install -y ssh-import-id",
      # Import the public keys for the users specified in the import_ssh_users variable.
      "ssh-import-id ${join(",", var.import_ssh_users)}",
    ]
  }
}

resource "linode_instance" "ops_o11y_leaders" {
  count     = var.leader_node_count
  image     = var.image_id
  label     = "ops-vm-o11y-wkr-${count.index + 1}"
  group     = "ops-o11y"
  region    = var.region
  type      = "g6-standard-2"
  root_pass = var.password

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = self.ip_address
  }

  provisioner "remote-exec" {
    inline = [
      # Update the system.
      "apt-get update -qq",
      # Disable password authentication; users can only connect with an SSH key.
      "sed -i '/PasswordAuthentication/d' /etc/ssh/sshd_config",
      "echo \"PasswordAuthentication no\" >> /etc/ssh/sshd_config",
      "apt-get install -y ssh-import-id",
      # Import the public keys for the users specified in the import_ssh_users variable.
      "ssh-import-id ${join(",", var.import_ssh_users)}",
    ]
  }
}
