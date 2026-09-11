output "firewall_id" {
  description = "gxy-fw-fra1 id. Import target for terraform import."
  value       = digitalocean_firewall.gxy_fra1.id
}
