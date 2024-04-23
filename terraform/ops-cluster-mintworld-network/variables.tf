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

# variable "cloudflare_api_token" {
#   type        = string
#   description = "Cloudflare API Token"
# }

# variable "cloudflare_account_id" {
#   type        = string
#   description = "Cloudflare Account ID"
# }

variable "region" {
  description = "The name of the region in which to deploy instances."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "region must be a valid AWS region name"
  }
}

# variable "network_subdomain" {
#   description = "The subdomain for the network."
#   type        = string
#   sensitive   = true

#   validation {
#     condition     = can(regex("^[a-z0-9-]+$", var.network_subdomain)) && length(var.network_subdomain) == 6
#     error_message = "network_subdomain must be a valid subdomain of 6 characters."
#   }
# }

variable "deployment_identifier" {
  description = "Environment for the network resources (3 letters)"
  type        = string
  default     = "ops"

  validation {
    condition     = length(var.deployment_identifier) == 3
    error_message = "deployment_identifier must be 3 characters long, ex: 'stg', 'prd'"
  }
}

variable "enable_eip_on_launch_in_public_subnets" {
  description = "Whether to enable EIP on launch in the public subnets"
  type        = bool
  default     = false
}

# -----------------------------------------------
# define the tags for the resources in this stack
# -----------------------------------------------
variable "stack_tags" {
  type        = map(string)
  description = "Tags to apply to all resources in this stack"
  default = {
    Stack = "mintworld"
  }
}
