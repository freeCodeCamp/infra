locals {
  linode_record_counts = {
    stg = {
      "freecodecamp.dev"          = 1
      "www.freecodecamp.dev"      = 1
      "api.freecodecamp.dev"      = 1
      "new-api.freecodecamp.dev"  = 1
      "chinese.freecodecamp.dev"  = 1
      "socrates.freecodecamp.dev" = 1
    }
    prd = {
      "freecodecamp.org"          = 3
      "www.freecodecamp.org"      = 3
      "api.freecodecamp.org"      = 3
      "chinese.freecodecamp.org"  = 3
      "socrates.freecodecamp.org" = 3
      "medium.freecodecamp.org"   = 1
      "news.freecodecamp.org"     = 1
      "blog.freecodecamp.org"     = 1
      "guide.freecodecamp.org"    = 1
      "chapter.freecodecamp.org"  = 1
      "meeting.freecodecamp.org"  = 1
    }
  }

  steps = { stg = var.stg_step, prd = var.prd_step }

  vultr_nodes = {
    stg = var.stg_step == "linode" ? {} : data.terraform_remote_state.stg[0].outputs.nodes
    prd = var.prd_step == "linode" ? {} : data.terraform_remote_state.prd[0].outputs.nodes
  }

  fleet_proxies = {
    for env, nodes in local.vultr_nodes : env => {
      for name, node in nodes : name => node.main_ip
      if node.role == "pxy"
    }
  }

  vultr_proxies = {
    for env, proxies in local.fleet_proxies : env => {
      for name, ip in proxies : name => ip
      if !contains(var.proxies_down, name)
    }
  }

  records = merge(flatten([
    for env, hosts in local.linode_record_counts : [
      for host, linode_count in hosts : {
        for key, content in merge(
          local.steps[env] == "100" ? {} : {
            for i, ip in slice(var.linode_origin_ips[env], 0, linode_count) : "linode-${i + 1}" => ip
          },
          {
            for name in slice(sort(keys(local.vultr_proxies[env])), 0, lookup(
              {
                linode = 0
                "25"   = linode_count > 1 ? min(1, length(local.vultr_proxies[env])) : 0
                "50"   = linode_count > 1 ? length(local.vultr_proxies[env]) : min(1, length(local.vultr_proxies[env]))
                "100"  = length(local.vultr_proxies[env])
              },
              local.steps[env]
            )) : name => local.vultr_proxies[env][name]
          }
        ) : "${host}/${key}" => { env = env, host = host, content = content }
      }
    ]
  ])...)
}

data "terraform_remote_state" "stg" {
  count = var.stg_step == "linode" ? 0 : 1

  backend = "s3"
  config  = merge(local.state_config, { key = "stg-vultr/terraform.tfstate" })
}

data "terraform_remote_state" "prd" {
  count = var.prd_step == "linode" ? 0 : 1

  backend = "s3"
  config  = merge(local.state_config, { key = "prd-vultr/terraform.tfstate" })
}

resource "terraform_data" "guard" {
  lifecycle {
    precondition {
      condition = alltrue([
        for env, step in local.steps : step == "linode" || (
          length(local.fleet_proxies[env]) == 3 &&
          length(local.vultr_proxies[env]) >= 1 &&
          alltrue([for name in var.proxies_down : contains(keys(local.fleet_proxies[env]), name) if startswith(name, "${env}-")])
        )
      ])
      error_message = "Each environment past the linode step needs exactly 3 Vultr proxies in its fleet state, at least 1 of them not marked down, and each name in proxies_down must be one of them."
    }
  }
}

resource "cloudflare_dns_record" "origin" {
  for_each = local.records

  zone_id = var.zone_ids[each.value.env]
  name    = each.value.host
  type    = "A"
  content = each.value.content
  proxied = true
  ttl     = 1

  depends_on = [terraform_data.guard]
}
