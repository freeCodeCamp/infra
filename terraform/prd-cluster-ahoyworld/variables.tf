variable "do_token" {
  description = "The Digital Ocean API token."
  type        = string
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token"
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare Account ID"
}
