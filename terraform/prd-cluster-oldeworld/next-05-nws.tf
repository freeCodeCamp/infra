resource "linode_instance" "prd_oldeworld_nws" {
  for_each = local.nws_instances
  label    = "prd-vm-oldeworld-nws-${each.value.name}"

  region     = var.region
  type       = "g6-standard-2"
  private_ip = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["prd", "oldeworld", "nws", "${each.value.name}"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "prd_oldeworld_nws"
}

resource "linode_instance_disk" "prd_oldeworld_nws_disk__boot" {
  for_each  = local.nws_instances
  label     = "prd-vm-oldeworld-nws-${each.value.name}-boot"
  linode_id = linode_instance.prd_oldeworld_nws[each.key].id
  size      = linode_instance.prd_oldeworld_nws[each.key].specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "nws-${each.value.name}.oldeworld.prd.${data.linode_domain.ops_dns_domain.domain}"
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

  devices {
    sda {
      disk_id = linode_instance_disk.prd_oldeworld_nws_disk__boot[each.key].id
    }
    sdb {
      volume_id = linode_volume.prd_oldeworld_nws_volume__data[each.key].id
    }
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
}

resource "linode_domain_record" "prd_oldeworld_nws_dnsrecord__vlan" {
  for_each = local.nws_instances

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "nws-${each.value.name}.oldeworld.prd"
  record_type = "A"
  target      = trimsuffix(linode_instance_config.prd_oldeworld_nws_config[each.key].interface[1].ipam_address, "/24")
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_oldeworld_nws_dnsrecord__public" {
  for_each = local.nws_instances

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.nws-${each.value.name}.oldeworld.prd.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.prd_oldeworld_nws[each.key].ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "prd_oldeworld_nws_dnsrecord__private" {
  for_each = local.nws_instances

  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "prv.nws-${each.value.name}.oldeworld.prd"
  record_type = "A"
  target      = linode_instance.prd_oldeworld_nws[each.key].private_ip_address
  ttl_sec     = 120
}

resource "linode_database_mysql" "prd_oldeworld_nws_db__mysql57" {
  engine_id = "mysql/5.7.39"
  label     = "prd-db-oldeworld-nws-mysql57"
  region    = var.region
  type      = "g6-dedicated-4"

  allow_list = flatten([
    [for i in linode_instance.prd_oldeworld_nws : "${i.private_ip_address}/32"]
  ])

  cluster_size     = 3
  replication_type = "asynch"
  ssl_connection   = true
}
