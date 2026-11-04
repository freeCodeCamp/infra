locals {
  team_keys = [for name in var.ssh_key_names : data.vultr_ssh_key.team[name].ssh_key]
}

data "vultr_vpc" "base" {
  filter {
    name   = "description"
    values = ["vultr-base-${var.region}"]
  }
}

data "vultr_firewall_group" "this" {
  for_each = toset([for node in var.nodes : node.firewall_group])

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
  source   = "../vultr-cloud-init"
  for_each = var.nodes

  hostname            = each.key
  ssh_authorized_keys = local.team_keys
}

resource "vultr_instance" "this" {
  for_each = var.nodes

  label             = each.key
  hostname          = each.key
  region            = var.region
  plan              = each.value.plan
  snapshot_id       = var.snapshot_id
  vpc_ids           = [data.vultr_vpc.base.id]
  firewall_group_id = data.vultr_firewall_group.this[each.value.firewall_group].id
  ssh_key_ids       = [for key in data.vultr_ssh_key.team : key.id]
  user_data         = module.cloud_init[each.key].user_data
  backups           = "disabled"
  tags              = [split("-", each.key)[0], each.value.role]

  lifecycle {
    ignore_changes = [snapshot_id, ssh_key_ids, user_data]
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "${abspath(path.module)}/tailscale-device-delete.sh"]
    command     = self.hostname
  }
}
