variable "linode_token" {
  description = "The Linode API Personal Access Token."
  type        = string
  sensitive   = true
}

variable "password" {
  description = "The root password for the Linode instances."
  type        = string
  sensitive   = true
}

variable "worker_node_count" {
  description = "The number of worker instances to create."
  default     = 3
  type        = number

  validation {
    condition     = var.worker_node_count > 0
    error_message = "The number of worker instances must atleast 1."
  }
}

variable "leader_node_count" {
  description = "The number of leader instances to create."
  default     = 1
  type        = number

  validation {
    condition     = var.leader_node_count > 0 && var.leader_node_count <= 3
    error_message = "The number of leader instances must be between 1-3."
  }
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

# variable "image_id" {
#   description = "The ID for the Linode image to be used in provisioning the instances"
#   default     = "private/20789403"
#   type        = string
# }

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
