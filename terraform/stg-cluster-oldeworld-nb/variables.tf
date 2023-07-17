variable "linode_token" {
  description = "The Linode API Personal Access Token."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east"
  type        = string
}
