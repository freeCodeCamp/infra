output "droplet_id" {
  value = digitalocean_droplet.ops_o11y.id
}

output "ipv4_address" {
  value = digitalocean_droplet.ops_o11y.ipv4_address
}
