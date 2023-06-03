# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInit"]
  }
}

# This data source depends on the domain resource
# which is created in terraform/ops-dns/main.tf
data "linode_domain" "ops_dns_domain" {
  domain = "freecodecamp.net"
}

resource "linode_instance" "ops_o11y_leaders" {
  count     = var.leader_node_count
  image     = var.image_id
  label     = "ops-vm-o11y-ldr-${count.index + 1}"
  group     = "ops-o11y"
  region    = var.region
  type      = "g6-standard-2"
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = "${var.userdata}"
  }

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
      # Set the hostname.
      "hostnamectl set-hostname ${self.label}"
    ]
  }
}

resource "linode_domain_record" "ops_o11y_leaders_records" {
  count = var.leader_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "ldr-${count.index + 1}.o11y.${data.linode_domain.ops_dns_domain.domain}"
  record_type = "A"
  target      = linode_instance.ops_o11y_leaders[count.index].ip_address
  ttl_sec     = 60
}

resource "linode_instance" "ops_o11y_workers" {
  count     = var.worker_node_count
  image     = var.image_id
  label     = "ops-vm-o11y-wkr-${count.index + 1}"
  group     = "ops-o11y"
  region    = var.region
  type      = "g6-standard-2"
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = "${var.userdata}"
  }

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
      "hostnamectl set-hostname ${self.label}"
    ]
  }
}

resource "linode_domain_record" "ops_o11y_workers_records" {
  count = var.worker_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "wkr-${count.index + 1}.o11y.${data.linode_domain.ops_dns_domain.domain}"
  record_type = "A"
  target      = linode_instance.ops_o11y_workers[count.index].ip_address
  ttl_sec     = 60
}
