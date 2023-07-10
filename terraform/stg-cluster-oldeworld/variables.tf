variable "linode_token" {
  description = "The Linode API Personal Access Token."
  type        = string
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

# variable "image_id" {
#   description = "The ID for the Linode image to be used in provisioning the instances"
#   default     = "private/20789403"
#   type        = string
# }

variable "hcp_client_id" {
  description = "The client ID for the HCP API."
  type        = string
}

variable "hcp_client_secret" {
  description = "The client secret for the HCP API."
  type        = string
}

