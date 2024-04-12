variable "region" {
  description = "The name of the region in which to deploy instances."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.region))
    error_message = "region must be a valid AWS region name"
  }
}

variable "network_env" {
  description = "Environment for the network resources (3 letters)"
  type        = string

  validation {
    condition     = length(var.network_env) == 3
    error_message = "network_env must be 3 characters long"
  }
}

variable "subnet_cidr_prefixes" {
  description = "The CIDR prefixes for the subnets"
  type        = list(string)
}

variable "enable_eip_on_launch_in_public_subnets" {
  description = "Whether to enable EIP on launch in the public subnets"
  type        = bool
  default     = false
}

variable "stack_tags" {
  description = "Tags to apply to the network resources"
  type        = map(string)
  default     = {}
}
