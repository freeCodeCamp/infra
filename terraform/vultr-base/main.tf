locals {
  vpc_description = "vultr-base-${var.region}"
  vpc_subnet      = cidrhost(var.vpc_cidr, 0)
  vpc_mask        = tonumber(split("/", var.vpc_cidr)[1])

  any_v4 = { ip_type = "v4", subnet = "0.0.0.0", subnet_size = 0 }
  any_v6 = { ip_type = "v6", subnet = "::", subnet_size = 0 }
  vpc_v4 = { ip_type = "v4", subnet = local.vpc_subnet, subnet_size = local.vpc_mask }

  common_rules = {
    "ssh-v4"  = merge(local.any_v4, { protocol = "tcp", port = "22", source = null })
    "ssh-v6"  = merge(local.any_v6, { protocol = "tcp", port = "22", source = null })
    "vpc-tcp" = merge(local.vpc_v4, { protocol = "tcp", port = "1:65535", source = null })
    "vpc-udp" = merge(local.vpc_v4, { protocol = "udp", port = "1:65535", source = null })
  }

  pxy_rules = {
    "http-cf-v4"  = merge(local.any_v4, { protocol = "tcp", port = "80", source = "cloudflare" })
    "http-cf-v6"  = merge(local.any_v6, { protocol = "tcp", port = "80", source = "cloudflare" })
    "https-cf-v4" = merge(local.any_v4, { protocol = "tcp", port = "443", source = "cloudflare" })
    "https-cf-v6" = merge(local.any_v6, { protocol = "tcp", port = "443", source = "cloudflare" })
  }

  firewall_group_rules = {
    base = local.common_rules
    pxy  = merge(local.common_rules, local.pxy_rules)
  }

  firewall_rules = merge([
    for group, rules in local.firewall_group_rules : {
      for name, rule in rules : "${group}/${name}" => merge(rule, { group = group })
    }
  ]...)
}

resource "vultr_vpc" "base" {
  region         = var.region
  description    = local.vpc_description
  v4_subnet      = local.vpc_subnet
  v4_subnet_mask = local.vpc_mask

  lifecycle {
    prevent_destroy = true
  }
}

resource "vultr_ssh_key" "team" {
  for_each = var.ssh_public_keys

  name    = each.key
  ssh_key = each.value
}

resource "vultr_firewall_group" "base" {
  description = "vultr-base"

  lifecycle {
    prevent_destroy = true
  }
}

resource "vultr_firewall_group" "pxy" {
  description = "vultr-pxy"

  lifecycle {
    prevent_destroy = true
  }
}

locals {
  firewall_group_ids = {
    base = vultr_firewall_group.base.id
    pxy  = vultr_firewall_group.pxy.id
  }
}

resource "vultr_firewall_rule" "this" {
  for_each = local.firewall_rules

  firewall_group_id = local.firewall_group_ids[each.value.group]
  protocol          = each.value.protocol
  ip_type           = each.value.ip_type
  subnet            = each.value.subnet
  subnet_size       = each.value.subnet_size
  port              = each.value.port
  source            = each.value.source
  notes             = each.key
}
