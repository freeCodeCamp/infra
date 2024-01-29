resource "linode_instance" "prd_oldeworld_api" {
  count = local.api_node_count
  label = "prd-vm-oldeworld-api-${count.index + 1}"

  region           = var.region
  type             = "g6-standard-2"
  private_ip       = true
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["prd", "oldeworld", "api"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "prd_oldeworld_api"
}

resource "linode_instance_disk" "prd_oldeworld_api_disk__boot" {
  count     = local.api_node_count
  label     = "prd-vm-oldeworld-api-${count.index + 1}-boot"
  linode_id = linode_instance.prd_oldeworld_api[count.index].id
  size      = linode_instance.prd_oldeworld_api[count.index].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "api-${count.index + 1}.oldeworld.prd.${local.zone}"
      })
    )
  }
}

resource "linode_instance_config" "prd_oldeworld_api_config" {
  count     = local.api_node_count
  label     = "prd-vm-oldeworld-api-config"
  linode_id = linode_instance.prd_oldeworld_api[count.index].id

  device {
    device_name = "sda"
    disk_id     = linode_instance_disk.prd_oldeworld_api_disk__boot[count.index].id
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
    ipam_address = "${cidrhost("10.0.0.0/8", local.ipam_block_api + count.index)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.prd_oldeworld_api[count.index].ip_address
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

resource "cloudflare_record" "prd_oldeworld_api_dnsrecord__vlan" {
  count = local.api_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "api-${count.index + 1}.oldeworld.prd"
  value = trimsuffix(linode_instance_config.prd_oldeworld_api_config[count.index].interface[1].ipam_address, "/24")
}

resource "cloudflare_record" "prd_oldeworld_api_dnsrecord__public" {
  count = local.api_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "pub.api-${count.index + 1}.oldeworld.prd.${var.network_subdomain}"
  value = linode_instance.prd_oldeworld_api[count.index].ip_address
}

resource "cloudflare_record" "prd_oldeworld_api_dnsrecord__private" {
  count = local.api_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "prv.api-${count.index + 1}.oldeworld.prd"
  value = linode_instance.prd_oldeworld_api[count.index].private_ip_address
}
