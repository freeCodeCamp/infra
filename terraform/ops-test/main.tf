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

resource "linode_instance" "ops_test" {
  label  = "ops-vm-test" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  tags = ["ops", "test", "ops_test"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "ops_test_disk__boot" {
  label     = "ops-vm-test-boot"
  linode_id = linode_instance.ops_test.id
  size      = linode_instance.ops_test.specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu.external_identifier
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "test.${local.zone}"
      })
    )
  }
}

resource "linode_instance_config" "ops_test_config" {
  label     = "ops-vm-test-config"
  linode_id = linode_instance.ops_test.id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.ops_test_disk__boot.id
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  # interface {
  #   purpose = "vlan"
  #   label   = "test-vlan"
  #   # Request the host IP for the machine
  #   ipam_address = "${cidrhost("10.0.0.0/8", 10 + 1)}/24"
  # }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_test.ip_address
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

resource "cloudflare_record" "ops_test_records" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "test"
  content = linode_instance.ops_test.ip_address
}

resource "cloudflare_record" "ops_test_records__public" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "pub.test.${var.network_subdomain}"
  content = linode_instance.ops_test.ip_address
}

resource "linode_firewall" "ops_test_firewall" {
  label = "ops-fw-test"

  inbound {
    label    = "allow-ssh"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [
    linode_instance.ops_test.id
  ]
}
