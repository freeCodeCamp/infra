output "bucket_name" {
  description = "Bucket name (matches var.bucket_name; preserved for downstream modules)"
  value       = cloudflare_r2_bucket.this.name
}

output "bucket_location" {
  description = "R2 jurisdiction of the live bucket"
  value       = cloudflare_r2_bucket.this.location
}

output "bucket_id" {
  description = "Provider-assigned bucket id (account_id/name form used for terraform import)"
  value       = cloudflare_r2_bucket.this.id
}
