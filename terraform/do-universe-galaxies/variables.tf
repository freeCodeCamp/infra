variable "galaxies" {
  description = <<-EOT
    Per-galaxy droplet topology. Key = galaxy slug (gxy-management,
    gxy-launchbase, gxy-cassiopeia). Inventory groups in
    `ansible/inventory/group_vars/` use the underscore variant
    (gxy_management_k3s); the slug here matches the k3s/<dir>/ on-disk
    layout instead.

    `node_count` is per-galaxy. Universe topology is single-node per
    galaxy today; bump when multi-node lands.

    `region` is fra1 for the production galaxies (per ADR-spike-plan);
    overrideable for staging.

    `tags` are applied verbatim and used by the ansible dynamic
    inventory keyed_groups rule (`do_tags | regex_replace ^_`). Keep
    the `_<galaxy>-k3s` shape — the leading underscore + hyphenated
    galaxy maps to the `<galaxy>_k3s` ansible group automatically.
  EOT

  type = map(object({
    node_count = number
    region     = string
    size       = string
    image      = string
    tags       = list(string)
  }))

  default = {
    "gxy-management" = {
      node_count = 1
      region     = "fra1"
      size       = "s-4vcpu-8gb"
      image      = "ubuntu-24-04-x64"
      tags       = ["_gxy-management-k3s", "k3s", "universe"]
    }
    "gxy-launchbase" = {
      node_count = 1
      region     = "fra1"
      size       = "s-2vcpu-4gb"
      image      = "ubuntu-24-04-x64"
      tags       = ["_gxy-launchbase-k3s", "k3s", "universe"]
    }
    "gxy-cassiopeia" = {
      node_count = 1
      region     = "fra1"
      size       = "s-2vcpu-4gb"
      image      = "ubuntu-24-04-x64"
      tags       = ["_gxy-cassiopeia-k3s", "k3s", "universe"]
    }
  }
}

variable "ssh_key_ids" {
  description = "DO SSH key ids attached to every droplet (output of `doctl compute ssh-key list`)."
  type        = list(number)
  default     = []
}

variable "vpc_ip_range_by_galaxy" {
  description = "RFC1918 IPv4 /24 per galaxy VPC. Pre-pinned so re-runs don't drift."
  type        = map(string)
  default = {
    "gxy-management" = "10.117.0.0/24"
    "gxy-launchbase" = "10.117.1.0/24"
    "gxy-cassiopeia" = "10.117.2.0/24"
  }
}

variable "operator_ssh_cidrs" {
  description = "CIDRs allowed inbound to droplet :22 + ICMP. Empty list = SSH + ICMP closed (operator MUST add their workstation/jumpbox CIDR before terraform apply or they'll lock themselves out)."
  type        = list(string)
  default     = []
}

# Cloudflare edge CIDRs. Published at https://www.cloudflare.com/ips-v4
# + /ips-v6 — refresh quarterly. These two variables narrow inbound
# HTTP/HTTPS on every galaxy firewall so CF-as-mandatory-proxy is
# enforced at the L3 layer (matches Flexible-SSL on the freecode.camp
# zone where CF→origin is plain HTTP — without this lockdown, anyone
# with the droplet IP can hit the origin and bypass the CF WAF).
#
# Defaults below are the CF ranges published at 2026-05-17. If
# Cloudflare adds a new range and the variable isn't refreshed,
# HTTP/HTTPS reads from those new IPs will be dropped at the firewall
# (visible as connection-resets at the CF edge → propagates as 521).
# That's the right failure mode — the operator notices fast and pulls
# the new list.
variable "cf_edge_cidrs_v4" {
  description = "Cloudflare published IPv4 edge ranges allowed inbound on 80/443."
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}

variable "cf_edge_cidrs_v6" {
  description = "Cloudflare published IPv6 edge ranges allowed inbound on 80/443."
  type        = list(string)
  default = [
    "2400:cb00::/32",
    "2606:4700::/32",
    "2803:f800::/32",
    "2405:b500::/32",
    "2405:8100::/32",
    "2a06:98c0::/29",
    "2c0f:f248::/32",
  ]
}
