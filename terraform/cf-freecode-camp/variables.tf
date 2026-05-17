variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read + DNS:Edit on freecode.camp"
  type        = string
  sensitive   = true
}

variable "zone_name" {
  description = "Apex DNS zone managed by this workspace"
  type        = string
  default     = "freecode.camp"
}

# Universe-platform ingress IPs by galaxy. cassiopeia fronts the
# `*.freecode.camp` wildcard (caddy-S3 over R2). gxy-management fronts
# `uploads.freecode.camp` (artemis deploy proxy). Sourced from
# DigitalOcean droplet IPv4 — re-pin via `doctl compute droplet list`
# whenever the load-balancer or floating IP rotates.
variable "cassiopeia_ingress_ipv4" {
  description = "Public IPv4 fronting *.freecode.camp (caddy-S3 / cassiopeia)"
  type        = string
}

variable "management_ingress_ipv4" {
  description = "Public IPv4 fronting uploads.freecode.camp (artemis / gxy-management)"
  type        = string
}
