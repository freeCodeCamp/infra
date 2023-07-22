resource "linode_instance" "prd_oldeworld_clt" {
  for_each = { for i in local.clt_instances : i.instance => i }
  label    = "prd-vm-oldeworld-clt-${each.value.instance}"

  region     = var.region
  type       = "g6-standard-2"
  private_ip = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["prd", "oldeworld", "clt", "${each.value.name}"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "prd_oldeworld_clt"
}

resource "linode_instance_disk" "prd_oldeworld_clt_disk__boot" {
  for_each  = { for i in local.clt_instances : i.instance => i }
  label     = "prd-vm-oldeworld-clt-${each.value.instance}-boot"
  linode_id = linode_instance.prd_oldeworld_clt[each.key].id
  size      = linode_instance.prd_oldeworld_clt[each.key].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "clt-${each.value.instance}.oldeworld.prd.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "prd_oldeworld_clt_config" {
  for_each  = { for i in local.clt_instances : i.instance => i }
  label     = "prd-vm-oldeworld-clt-config"
  linode_id = linode_instance.prd_oldeworld_clt[each.key].id

  devices {
    sda {
      disk_id = linode_instance_disk.prd_oldeworld_clt_disk__boot[each.key].id
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
    ipam_address = "${cidrhost("10.0.0.0/8", tonumber(each.value.ipam_id))}/24"
  }

  connection {
    type     = "ssh"
    user     = "root"
    password = var.password
    host     = linode_instance.prd_oldeworld_clt[each.key].ip_address
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

resource "linode_domain_record" "prd_oldeworld_clt_dnsrecord__vlan" {
  for_each = { for i in local.clt_instances : i.instance => i }

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "clt-${each.value.instance}.oldeworld.prd"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.prd_oldeworld_clt_config[each.key].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_oldeworld_clt_dnsrecord__public" {
  for_each = { for i in local.clt_instances : i.instance => i }

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.clt-${each.value.instance}.oldeworld.prd.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.prd_oldeworld_clt[each.key].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_oldeworld_clt_dnsrecord__private" {
  for_each = { for i in local.clt_instances : i.instance => i }

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.clt-${each.value.instance}.oldeworld.prd"
  record_type = "A"
  target      = linode_instance.prd_oldeworld_clt[each.key].private_ip_address
  ttl_sec     = 120
}
