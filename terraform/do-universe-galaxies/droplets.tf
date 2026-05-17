locals {
  # Flatten the galaxies map into one row per droplet so for_each
  # can key on `<galaxy>-<index>` (e.g. `gxy-management-01`).
  #
  # Using a for-loop with for_each over `setunion` of strings keeps
  # the keys stable across re-orderings of the input map — the
  # documented Terraform pattern to avoid index-based blast radius
  # (per ~/.claude/rules/75-terraform.md).
  droplet_rows = merge([
    for galaxy, cfg in var.galaxies : {
      for i in range(1, cfg.node_count + 1) :
      "${galaxy}-${format("%02d", i)}" => merge(cfg, {
        galaxy = galaxy
        index  = i
      })
    }
  ]...)
}

resource "digitalocean_droplet" "this" {
  for_each = local.droplet_rows

  name   = each.key
  region = each.value.region
  size   = each.value.size
  image  = each.value.image
  tags   = each.value.tags

  vpc_uuid = digitalocean_vpc.this[each.value.galaxy].id
  ssh_keys = var.ssh_key_ids

  # Disable backups by default — k3s state lives in CNPG / Valkey
  # / R2 already; per-droplet image backups are wasted spend.
  backups = false

  # Disable IPv6 — Cilium config doesn't dual-stack today.
  ipv6 = false

  # Monitoring agent collects droplet metrics into DO's dashboard.
  monitoring = true

  lifecycle {
    prevent_destroy = true
    # The DO API stamps `created_at` + image-version drift on every
    # plan; ignore them so a tf apply doesn't trigger a destroy /
    # recreate cycle on the prevent_destroy guard.
    ignore_changes = [
      image,
    ]
  }
}
