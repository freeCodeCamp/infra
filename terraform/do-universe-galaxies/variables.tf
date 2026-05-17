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
  description = "CIDRs allowed inbound to droplet :22. Empty list = SSH closed (operator MUST add their workstation/jumpbox CIDR before terraform apply or they'll lock themselves out)."
  type        = list(string)
  default     = []
}
