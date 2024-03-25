locals {
  zone = "freecodecamp.net"
}

# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInitfreeCodeCamp"]
  }
  filter {
    name   = "is_public"
    values = ["false"]
  }
}

data "hcp_packer_artifact" "linode_ubuntu" {
  bucket_name  = "linode-ubuntu"
  channel_name = "golden"
  platform     = "linode"
  region       = "us-east"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}

resource "linode_instance" "ops_o11y_leaders" {
  count  = var.leader_node_count
  label  = "ops-vm-o11y-ldr-${count.index + 1}"
  group  = "o11y_leader" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  private_ip       = true
  watchdog_enabled = true

  tags = ["ops", "o11y", "o11y_leader"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "ops_o11y_leaders_disk__boot" {
  count     = var.leader_node_count
  label     = "ops-vm-o11y-ldr-${count.index + 1}-boot"
  linode_id = linode_instance.ops_o11y_leaders[count.index].id
  size      = linode_instance.ops_o11y_leaders[count.index].specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu.id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "ldr-${count.index + 1}.o11y"
      })
    )
  }
}

resource "linode_instance_config" "ops_o11y_leaders_config" {
  count     = var.leader_node_count
  label     = "ops-vm-o11y-ldr-config"
  linode_id = linode_instance.ops_o11y_leaders[count.index].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.ops_o11y_leaders_disk__boot[count.index].id
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "o11y-vlan"
    # Request the host IP for the machine
    ipam_address = "${cidrhost("10.0.0.0/8", 10 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_o11y_leaders[count.index].ip_address
  }

  # All of the provisioning should be done via cloud-init.
  # This is just to setup the reboot.
  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish.
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo Current hostname...; hostname",
      "shutdown -r +1 'Terraform: Rebooting to apply hostname change in 1 min.'"
    ]
  }

  # This run is a hack to trigger the reboot,
  # which may fail otherwise in the previous step.
  provisioner "remote-exec" {
    inline = [
      "uptime"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  kernel = "linode/grub2"
  booted = true

  lifecycle {
    ignore_changes = [
      booted
    ]
  }
}

resource "cloudflare_record" "ops_o11y_leaders_dnsrecord__vlan" {
  count = var.leader_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "ldr-${count.index + 1}.o11y"
  value = trimsuffix(linode_instance_config.ops_o11y_leaders_config[count.index].interface[1].ipam_address, "/24")
}

resource "cloudflare_record" "ops_o11y_leaders_dnsrecord__public" {
  count = var.leader_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "pub.ldr-${count.index + 1}.o11y.${var.network_subdomain}"
  value = linode_instance.ops_o11y_leaders[count.index].ip_address
}

resource "cloudflare_record" "ops_o11y_leaders_dnsrecord__private" {
  count = var.leader_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "prv.ldr-${count.index + 1}.o11y"
  value = linode_instance.ops_o11y_leaders[count.index].private_ip_address
}

resource "linode_instance" "ops_o11y_workers" {
  count  = var.worker_node_count
  label  = "ops-vm-o11y-wkr-${count.index + 1}"
  group  = "o11y_worker" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  private_ip       = true
  watchdog_enabled = true

  tags = ["ops", "o11y", "o11y_worker"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "ops_o11y_workers_disk__boot" {
  count     = var.worker_node_count
  label     = "ops-vm-o11y-wkr-${count.index + 1}-boot"
  linode_id = linode_instance.ops_o11y_workers[count.index].id
  size      = linode_instance.ops_o11y_workers[count.index].specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu.id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "wkr-${count.index + 1}.o11y"
      })
    )
  }
}

resource "linode_instance_config" "ops_o11y_workers_config" {
  count     = var.worker_node_count
  label     = "ops-vm-o11y-wkr-config"
  linode_id = linode_instance.ops_o11y_workers[count.index].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.ops_o11y_workers_disk__boot[count.index].id
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "o11y-vlan"
    # This results in IPAM address like 10.0.0.21/24, 10.0.0.22/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", 20 + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_o11y_workers[count.index].ip_address
  }

  # All of the provisioning should be done via cloud-init.
  # This is just to setup the reboot.
  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish.
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo Current hostname...; hostname",
      "shutdown -r +1 'Terraform: Rebooting to apply hostname change in 1 min.'"
    ]
  }

  # This run is a hack to trigger the reboot,
  # which may fail otherwise in the previous step.
  provisioner "remote-exec" {
    inline = [
      "uptime"
    ]
  }

  helpers {
    updatedb_disabled = true
  }

  kernel = "linode/grub2"
  booted = true

  lifecycle {
    ignore_changes = [
      booted
    ]
  }
}

resource "cloudflare_record" "ops_o11y_workers_dnsrecord__vlan" {
  count = var.worker_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "wkr-${count.index + 1}.o11y"
  value = trimsuffix(linode_instance_config.ops_o11y_workers_config[count.index].interface[1].ipam_address, "/24")
}

resource "cloudflare_record" "ops_o11y_workers_dnsrecord__public" {
  count = var.worker_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "pub.wkr-${count.index + 1}.o11y.${var.network_subdomain}"
  value = linode_instance.ops_o11y_workers[count.index].ip_address
}

resource "cloudflare_record" "ops_o11y_workers_dnsrecord__private" {
  count = var.worker_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "prv.wkr-${count.index + 1}.o11y"
  value = linode_instance.ops_o11y_workers[count.index].private_ip_address
}

resource "linode_firewall" "ops_o11y_firewall" {
  label = "ops-fw-o11y"

  inbound {
    label    = "allow-ssh_from-anywhere"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-tcp_within-cluster"
    ports    = "1-65535"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in linode_instance.ops_o11y_leaders : "${i.private_ip_address}/32"],
      [for i in linode_instance.ops_o11y_workers : "${i.private_ip_address}/32"]
    ])
  }

  inbound {
    label    = "allow-udp_within-cluster"
    ports    = "1-65535"
    protocol = "UDP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in linode_instance.ops_o11y_leaders : "${i.private_ip_address}/32"],
      [for i in linode_instance.ops_o11y_workers : "${i.private_ip_address}/32"]
    ])
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    [for i in linode_instance.ops_o11y_leaders : i.id],
    [for i in linode_instance.ops_o11y_workers : i.id],
  ])
}
