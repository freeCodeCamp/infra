variable "linode_token" {
  description = "The Linode API Personal Access Token."
  type        = string
  sensitive   = true
}

variable "password" {
  description = "The root password for the Linode instances."
  type        = string
}

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east"
  type        = string
}

variable "network_subdomain" {
  description = "The subdomain for the network."
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
