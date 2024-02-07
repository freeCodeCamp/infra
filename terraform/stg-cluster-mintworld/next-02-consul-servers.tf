resource "linode_instance" "stg_mintworld_consul_svr" {
  count = local.consul_svr_count
  label = "stg-mintworld-consul-svr-${count.index + 1}"

  region           = var.region
  type             = "g6-standard-2"
  private_ip       = true
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["stg", "mintworld", "consul_svr"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "stg_mintworld_consul_svr"

  metadata {
    user_data = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "nomad-svr-${count.index + 1}.mintworld.stg.${local.zone}"
      })
    )
  }

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "stg_mintworld_consul_svr_disk__boot" {
  count     = local.consul_svr_count
  label     = "stg-mintworld-consul-svr-${count.index + 1}-boot"
  linode_id = linode_instance.stg_mintworld_consul_svr[count.index].id
  size      = linode_instance.stg_mintworld_consul_svr[count.index].specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu_artifact.external_identifier
  root_pass = var.password
}

resource "linode_instance_config" "stg_mintworld_consul_svr_config" {
  count     = local.consul_svr_count
  label     = "stg-vm-mintworld-consul-svr-config"
  linode_id = linode_instance.stg_mintworld_consul_svr[count.index].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.stg_mintworld_consul_svr_disk__boot[count.index].id
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "stg-mintworld-vlan"
    # Request the host IP for the machine
    ipam_address = "${cidrhost("10.0.0.0/8", local.ipam_block_consul_svr + count.index)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.stg_mintworld_consul_svr[count.index].ip_address
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

  kernel = "linode/latest-64bit"
  booted = true

  lifecycle {
    ignore_changes = [
      booted
    ]
  }
}

resource "cloudflare_record" "stg_mintworld_consul_svr_dnsrecord__vlan" {
  count = local.consul_svr_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "consul-svr-${count.index + 1}.mintworld.stg"
  value = trimsuffix(linode_instance_config.stg_mintworld_consul_svr_config[count.index].interface[1].ipam_address, "/24")
}

resource "cloudflare_record" "stg_mintworld_consul_svr_dnsrecord__public" {
  count = local.consul_svr_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "pub.consul-svr-${count.index + 1}.mintworld.stg.${var.network_subdomain}"
  value = linode_instance.stg_mintworld_consul_svr[count.index].ip_address
}

resource "cloudflare_record" "stg_mintworld_consul_svr_dnsrecord__private" {
  count = local.consul_svr_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "prv.consul-svr-${count.index + 1}.mintworld.stg"
  value = linode_instance.stg_mintworld_consul_svr[count.index].private_ip_address
}
