output "droplet_ids" {
  value = { for key, node in digitalocean_droplet.ops_o11y : key => node.id }
}

output "ipv4_addresses" {
  value = { for key, node in digitalocean_droplet.ops_o11y : key => node.ipv4_address }
}
