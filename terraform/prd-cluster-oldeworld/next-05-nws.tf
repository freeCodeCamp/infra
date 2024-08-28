resource "linode_instance" "prd_oldeworld_nws" {
  for_each = local.nws_instances
  label    = "prd-vm-oldeworld-nws-${each.value.name}"

  region           = var.region
  type             = "g6-standard-2"
  private_ip       = true
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["prd", "oldeworld", "nws", "prd_oldeworld_nws", "${each.value.name}"]

  lifecycle {
    ignore_changes = [
      migration_type
    ]
  }
}

resource "linode_instance_disk" "prd_oldeworld_nws_disk__boot" {
  for_each  = local.nws_instances
  label     = "prd-vm-oldeworld-nws-${each.value.name}-boot"
  linode_id = linode_instance.prd_oldeworld_nws[each.key].id
  size      = linode_instance.prd_oldeworld_nws[each.key].specs.0.disk

  image     = data.hcp_packer_artifact.linode_ubuntu.external_identifier
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "nws-${each.value.name}.oldeworld.prd.${local.zone}"
      })
    )
  }
}

resource "linode_volume" "prd_oldeworld_nws_volume__data" {
  for_each = local.nws_instances
  label    = "prd-vm-oldeworld-nws-${each.value.name}-data"
  size     = 120
  region   = var.region
}

resource "linode_instance_config" "prd_oldeworld_nws_config" {
  for_each  = local.nws_instances
  label     = "prd-vm-oldeworld-nws-config"
  linode_id = linode_instance.prd_oldeworld_nws[each.key].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.prd_oldeworld_nws_disk__boot[each.key].id
  }

  device {
    device_name = "sdb"
    volume_id   = linode_volume.prd_oldeworld_nws_volume__data[each.key].id
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "prd-oldeworld-vlan"
    # Request the host IP for the machine
    ipam_address = "${cidrhost("10.0.0.0/8", tonumber(local.ipam_block_nws + each.value.ipam_id))}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.prd_oldeworld_nws[each.key].ip_address
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

resource "cloudflare_record" "prd_oldeworld_nws_dnsrecord__vlan" {
  for_each = local.nws_instances

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "nws-${each.value.name}.oldeworld.prd"
  content = trimsuffix(linode_instance_config.prd_oldeworld_nws_config[each.key].interface[1].ipam_address, "/24")
}

resource "cloudflare_record" "prd_oldeworld_nws_dnsrecord__public" {
  for_each = local.nws_instances

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "pub.nws-${each.value.name}.oldeworld.prd.${var.network_subdomain}"
  content = linode_instance.prd_oldeworld_nws[each.key].ip_address
}

resource "cloudflare_record" "prd_oldeworld_nws_dnsrecord__private" {
  for_each = local.nws_instances

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "prv.nws-${each.value.name}.oldeworld.prd"
  content = linode_instance.prd_oldeworld_nws[each.key].private_ip_address
}
