output "vpc_ids" {
  description = "DO VPC id by galaxy."
  value       = { for k, v in digitalocean_vpc.this : k => v.id }
}

output "firewall_ids" {
  description = "DO cloud-firewall id by galaxy."
  value       = { for k, v in digitalocean_firewall.this : k => v.id }
}

output "droplet_ids" {
  description = "Droplet id keyed by `<galaxy>-NN`."
  value       = { for k, v in digitalocean_droplet.this : k => v.id }
}

output "droplet_ipv4" {
  description = "Public IPv4 keyed by `<galaxy>-NN` — feed into cf-freecode-camp/variables.tfvars."
  value       = { for k, v in digitalocean_droplet.this : k => v.ipv4_address }
}

output "droplet_ipv4_private" {
  description = "VPC-private IPv4 (cluster-internal hops)."
  value       = { for k, v in digitalocean_droplet.this : k => v.ipv4_address_private }
}
