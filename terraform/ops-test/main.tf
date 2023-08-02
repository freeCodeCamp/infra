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

# This data source depends on the domain resource
# which is created in terraform/ops-dns/main.tf
data "linode_domain" "ops_dns_domain" {
  domain = "freecodecamp.net"
}

data "hcp_packer_image" "linode_ubuntu" {
  bucket_name    = "linode-ubuntu"
  channel        = "golden"
  cloud_provider = "linode"
  region         = "us-east"
}

resource "linode_instance" "ops_test" {
  label  = "ops-vm-test"
  group  = "test" # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
  region = var.region
  type   = "g6-standard-2"

  tags = ["ops", "test"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_instance_disk" "ops_test_disk__boot" {
  label     = "ops-vm-test-boot"
  linode_id = linode_instance.ops_test.id
  size      = linode_instance.ops_test.specs.0.disk

  image     = data.hcp_packer_image.linode_ubuntu.cloud_image_id
  root_pass = var.password

  stackscript_id = data.linode_stackscripts.cloudinit_scripts.stackscripts.0.id
  stackscript_data = {
    userdata = base64encode(
      templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
        tf_hostname = "test.${data.linode_domain.ops_dns_domain.domain}"
      })
    )
  }
}

resource "linode_instance_config" "ops_test_config" {
  label     = "ops-vm-test-config"
  linode_id = linode_instance.ops_test.id

  devices {
    sda {
      disk_id = linode_instance_disk.ops_test_disk__boot.id
    }
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
}

resource "linode_domain_record" "ops_test_records" {
  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "test"
  record_type = "A"
  target      = linode_instance.ops_test.ip_address
  ttl_sec     = 120
}

resource "linode_domain_record" "ops_test_dnsrecord__public" {
  domain_id   = data.linode_domain.ops_dns_domain.id
  name        = "pub.test.${var.network_subdomain}"
  record_type = "A"
  target      = linode_instance.ops_test.ip_address
  ttl_sec     = 120
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
