resource "digitalocean_vpc" "this" {
  for_each = var.galaxies

  name     = "vpc-${each.key}"
  region   = each.value.region
  ip_range = var.vpc_ip_range_by_galaxy[each.key]

  description = "Universe galaxy ${each.key} private network — k3s control plane + node-to-node traffic."

  lifecycle {
    prevent_destroy = true
  }
}
