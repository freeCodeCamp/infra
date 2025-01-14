resource "linode_instance" "ops_backoffice" {
  label = "ops-vm-backoffice"

  region           = var.region
  type             = "g6-standard-2"
  private_ip       = true
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["ops", "backoffice", "ops_backoffice"]

  backups_enabled = true

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "ops_backoffice_disk__boot" {
  label     = "ops-vm-backoffice-boot"
  linode_id = linode_instance.ops_backoffice.id
  size      = linode_instance.ops_backoffice.specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu.external_identifier
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "backoffice.${local.zone}"
      })
    )
  }
}

resource "linode_instance_config" "ops_backoffice_config" {
  label     = "ops-vm-backoffice-config"
  linode_id = linode_instance.ops_backoffice.id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.ops_backoffice_disk__boot.id
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

  lifecycle {
    ignore_changes = [
      booted
    ]
  }
}

resource "cloudflare_record" "ops_backoffice_dnsrecord__public" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "pub.backoffice.${var.network_subdomain}"
  content = linode_instance.ops_backoffice.ip_address
}

resource "cloudflare_record" "ops_backoffice_dnsrecord__private" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "prv.backoffice"
  content = linode_instance.ops_backoffice.private_ip_address
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
    label    = "allow-all-tcp-jms"
    ports    = "1-65535"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in data.linode_instances.stg_oldeworld_jms.instances : "${i.private_ip_address}/32"],
      [for i in data.linode_instances.prd_oldeworld_jms.instances : "${i.private_ip_address}/32"],
      [for i in data.linode_instances.stg_oldeworld_api.instances :
        contains(i.tags, "new_api") ? ["${i.private_ip_address}/32"] : []
      ],
      [for i in data.linode_instances.prd_oldeworld_api.instances :
        contains(i.tags, "new_api") ? ["${i.private_ip_address}/32"] : []
      ]
    ])
  }

  inbound {
    label    = "allow-all-udp-jms"
    ports    = "1-65535"
    protocol = "UDP"
    action   = "ACCEPT"
    ipv4 = flatten([
      [for i in data.linode_instances.stg_oldeworld_jms.instances : "${i.private_ip_address}/32"],
      [for i in data.linode_instances.prd_oldeworld_jms.instances : "${i.private_ip_address}/32"],
      [for i in data.linode_instances.stg_oldeworld_api.instances :
        contains(i.tags, "new_api") ? ["${i.private_ip_address}/32"] : []
      ],
      [for i in data.linode_instances.prd_oldeworld_api.instances :
        contains(i.tags, "new_api") ? ["${i.private_ip_address}/32"] : []
      ]
    ])
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = [
    linode_instance.ops_backoffice.id
  ]
}
