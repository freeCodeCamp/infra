output "zone_id" {
  description = "Cloudflare zone id for freecode.camp"
  value       = data.cloudflare_zone.this.id
}

output "records" {
  description = "Map of managed DNS record ids keyed by local.records key"
  value       = { for k, r in cloudflare_record.this : k => r.id }
}
