variable "do_token" {
  description = "The Digital Ocean API token."
  type        = string
  sensitive   = true
}

variable "hcp_client_id" {
  description = "The client ID for the HCP API."
  type        = string
  sensitive   = true
}

variable "hcp_client_secret" {
  description = "The client secret for the HCP API."
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

variable "network_subdomain" {
  description = "The subdomain for the network."
  type        = string
  sensitive   = true
}

variable "ssh_terraform_ed25519_private_key" {
  type        = string
  description = "The private key for the terraform account."
  sensitive   = true
}
