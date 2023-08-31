resource "linode_instance" "ops_backoffice" {
  label = "ops-vm-backoffice"

  region           = var.region
  type             = "g6-standard-2"
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["ops", "backoffice"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "backoffice"
}

resource "linode_instance_disk" "ops_backoffice_disk__boot" {
  label     = "ops-vm-backoffice-boot"
  linode_id = linode_instance.ops_backoffice.id
  size      = linode_instance.ops_backoffice.specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "backoffice.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "ops_backoffice_config" {
  label     = "ops-vm-backoffice-config"
  linode_id = linode_instance.ops_backoffice.id

  devices {
    sda {
      disk_id = linode_instance_disk.ops_backoffice_disk__boot.id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.ops_backoffice.ip_address
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
}

resource "linode_domain_record" "ops_backoffice_dnsrecord__public" {
  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.backoffice.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.ops_backoffice.ip_address
  ttl_sec     = 120
}

resource "akamai_dns_record" "ops_backoffice_dnsrecord__public" {
  zone       = local.zone
  name       = "pub.backoffice.${var.network_subdomain}.${local.zone}"
  recordtype = "A"
  target     = [linode_instance.ops_backoffice.ip_address]
  ttl        = 120
}

resource "linode_firewall" "ops_backoffice_firewall" {
  label = "ops-fw-backoffice"

  inbound {
    label    = "allow-ssh"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-http"
    ports    = "80"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-https"
    ports    = "443"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [
    linode_instance.ops_backoffice.id
  ]
}
