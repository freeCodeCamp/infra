resource "linode_instance" "stg_oldeworld_cltita" {
  count  = local.cltita_node_count
  label  = "stg-vm-oldeworld-cltita-${count.index + 1}"
  group  = "oldeworld_cltita" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  private_ip = true

  tags = ["stg", "oldeworld", "oldeworld_cltita"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_instance_disk" "stg_oldeworld_cltita_disk__boot" {
  count     = local.cltita_node_count
  label     = "stg-vm-oldeworld-cltita-${count.index + 1}-boot"
  linode_id = linode_instance.stg_oldeworld_cltita[count.index].id
  size      = linode_instance.stg_oldeworld_cltita[count.index].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "cltita-${count.index + 1}.oldeworld.stg.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "stg_oldeworld_cltita_config" {
  count     = local.cltita_node_count
  label     = "stg-vm-oldeworld-cltita-config"
  linode_id = linode_instance.stg_oldeworld_cltita[count.index].id

  devices {
    sda {
      disk_id = linode_instance_disk.stg_oldeworld_cltita_disk__boot[count.index].id
    }
  }

  # eth0 is the public interface.
  interface {
    purpose = "public"
  }

  # eth1 is the private interface.
  interface {
    purpose = "vlan"
    label   = "oldeworld-vlan"
    # This results in IPAM address like 10.0.0.11/24, 10.0.0.12/24, etc.
    ipam_address = "${cidrhost("10.0.0.0/8", local.ipam_block_cltita + count.index + 1)}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.stg_oldeworld_cltita[count.index].ip_address
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

  booted = true
}

resource "linode_domain_record" "stg_oldeworld_cltita_dnsrecord__vlan" {
  count = local.cltita_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "cltita-${count.index + 1}.oldeworld.stg"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.stg_oldeworld_cltita_config[count.index].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_domain_record" "stg_oldeworld_cltita_dnsrecord__public" {
  count = local.cltita_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.cltita-${count.index + 1}.oldeworld.stg.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.stg_oldeworld_cltita[count.index].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "stg_oldeworld_cltita_dnsrecord__private" {
  count = local.cltita_node_count

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.cltita-${count.index + 1}.oldeworld.stg"
  record_type = "A"
  target      = linode_instance.stg_oldeworld_cltita[count.index].private_ip_address
  ttl_sec     = 120
}
