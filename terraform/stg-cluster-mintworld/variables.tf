variable "aws_access_key_id" {
  description = "The value of the AWS Access Key ID."
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "The value of the AWS Secret Access Key."
  type        = string
  sensitive   = true
}

variable "tailscale_auth_key" {
  description = "The Tailscale authentication key."
  type        = string
  sensitive   = true
}
variable "password" {
  description = "The root password for the Linode instances."
  type        = string
}

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east-1"
  type        = string
}

variable "network_subdomain" {
  description = "The subdomain for the network."
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

variable "user_data_replace_on_change" {
  type        = bool
  description = "Recreate instances on changes to UserData"
  default     = false
}

variable "enable_eip_on_launch_in_public_subnets" {
  type        = bool
  description = "Enable EIP assignment on launch in public subnets"
  default     = false
}

# -----------------------------------------------
# define the tags for the resources in this stack
# -----------------------------------------------
variable "stack_tags" {
  type        = map(string)
  description = "Tags to apply to all resources in this stack"
  default = {
    Environment = "stg"
    Stack       = "mintworld"
  }
}
