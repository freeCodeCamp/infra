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

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east-1"
  type        = string
}

variable "instance_type" {
  description = "Default instance type."
  default     = "t3a.medium"
  type        = string
}

variable "instance_type_prv_routers" {
  description = "Instance type for private routers."
  default     = "t3.nano"
  type        = string
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

variable "tailscale_tailnet" {
  description = "The Tailnet ID for the Tailscale network."
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_id" {
  description = "The OAuth client ID for the Tailscale network."
  type        = string
  sensitive   = true
}

variable "tailscale_oauth_client_secret" {
  description = "The OAuth client secret for the Tailscale network."
  type        = string
  sensitive   = true
}

# -----------------------------------------------
# define the tags for the resources in this stack
# -----------------------------------------------
variable "stack_tags" {
  type        = map(string)
  description = "Tags to apply to all resources in this stack"
  default = {
    Environment = "ops"
    Stack       = "mintworld"
  }
}
