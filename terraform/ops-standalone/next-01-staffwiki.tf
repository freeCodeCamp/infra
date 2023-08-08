resource "linode_instance" "ops_staffwiki" {
  label = "ops-vm-staffwiki"

  region           = var.region
  type             = "g6-standard-2"
  watchdog_enabled = true

  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  tags = ["prd", "staffwiki"]

  # WARNING:
  # Do not change, will delete and recreate all instances in the group
  # NOTE:
  # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  group = "staffwiki"
}

resource "linode_instance_disk" "ops_staffwiki_disk__boot" {
  label     = "ops-vm-staffwiki-boot"
  linode_id = linode_instance.ops_staffwiki.id
  size      = linode_instance.ops_staffwiki.specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "staffwiki.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "ops_staffwiki_config" {
  label     = "ops-vm-staffwiki-config"
  linode_id = linode_instance.ops_staffwiki.id

  devices {
    sda {
      disk_id = linode_instance_disk.ops_staffwiki_disk__boot.id
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
    host     = linode_instance.ops_staffwiki.ip_address
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

resource "linode_domain_record" "ops_staffwiki_dnsrecord__public" {
  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.staffwiki.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.ops_staffwiki.ip_address
  ttl_sec     = 120
}

resource "linode_firewall" "ops_staffwiki_firewall" {
  label = "ops-fw-staffwiki"

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
    linode_instance.ops_staffwiki.id
  ]
}

data "linode_object_storage_cluster" "ops_staffwiki_osc__primary" {
  id = "${var.region}-1"
}

resource "linode_object_storage_bucket" "ops_staffwiki_bucket" {
  cluster = data.linode_object_storage_cluster.ops_staffwiki_osc__primary.id
  label   = "staffwiki"
}

resource "linode_object_storage_key" "ops_staffwiki_key" {
  label = "staffwiki-default-key"

  bucket_access {
    bucket_name = linode_object_storage_bucket.ops_staffwiki_bucket.label
    permissions = "read_write"
    cluster     = data.linode_object_storage_cluster.ops_staffwiki_osc__primary.id
  }
}
