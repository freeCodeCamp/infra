locals {
  env  = "stg"
  plan = "vc2-2c-4gb"

  counts = { pxy = 3, api = 3, soc = 3, nws = 3 }
  client_langs = [
    "eng", "chn", "esp", "ita", "jpn", "por", "ukr", "ger", "cnt", "swa", "kor", "ara",
  ]

  role_nodes = merge([
    for role, count in local.counts : {
      for n in range(1, count + 1) : "${local.env}-vm-${role}-${n}" => {
        role           = role
        plan           = local.plan
        firewall_group = role == "pxy" ? "vultr-pxy" : "vultr-base"
      }
    }
  ]...)

  client_nodes = merge([
    for lang in local.client_langs : {
      for n in range(0, 2) : "${local.env}-vm-clt-${lang}-${n}" => {
        role           = "clt"
        plan           = local.plan
        firewall_group = "vultr-base"
      }
    }
  ]...)
}

module "fleet" {
  source = "../modules/vultr-fleet"

  nodes         = merge(local.role_nodes, local.client_nodes)
  snapshot_id   = var.snapshot_id
  ssh_key_names = var.ssh_key_names
}
