locals {
  nodes = {
    "tst-vm-pxy-1" = { role = "pxy", firewall_group = "vultr-pxy" }
    "tst-vm-mgr-1" = { role = "mgr", firewall_group = "vultr-base" }
    "tst-vm-wkr-1" = { role = "wkr", firewall_group = "vultr-base" }
  }

  team_keys = [for name in var.ssh_key_names : data.vultr_ssh_key.team[name].ssh_key]
}

data "vultr_vpc" "base" {
  filter {
    name   = "description"
    values = ["vultr-base-${var.region}"]
  }
}

data "vultr_firewall_group" "this" {
  for_each = toset([for node in local.nodes : node.firewall_group])

  filter {
    name   = "description"
    values = [each.key]
  }
}

data "vultr_ssh_key" "team" {
  for_each = toset(var.ssh_key_names)

  filter {
    name   = "name"
    values = [each.key]
  }
}

module "cloud_init" {
  source   = "../modules/vultr-cloud-init"
  for_each = local.nodes

  hostname            = each.key
  ssh_authorized_keys = local.team_keys
}

resource "vultr_instance" "tst" {
  for_each = local.nodes

  label             = each.key
  hostname          = each.key
  region            = var.region
  plan              = var.plan
  snapshot_id       = var.snapshot_id
  vpc_ids           = [data.vultr_vpc.base.id]
  firewall_group_id = data.vultr_firewall_group.this[each.value.firewall_group].id
  ssh_key_ids       = [for key in data.vultr_ssh_key.team : key.id]
  user_data         = module.cloud_init[each.key].user_data
  backups           = "disabled"
  tags              = ["tst", each.value.role]

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "${abspath(path.module)}/../modules/vultr-fleet/tailscale-device-delete.sh"]
    command     = self.hostname
  }
}
