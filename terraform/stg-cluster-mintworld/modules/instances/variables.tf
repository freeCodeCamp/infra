variable "instance_env" {
  description = "Environment for the instance (3 letters)"
  type        = string

  validation {
    condition     = length(var.instance_env) == 3
    error_message = "instance_env must be 3 characters long"
  }
}

variable "instance_prefix" {
  description = "Prefix for the instance name"
  type        = string

  validation {
    condition     = length(var.instance_prefix) <= 10
    error_message = "instance_prefix must be 10 characters or less"
  }
}

variable "instance_count" {
  description = "Number of instances to create"
  type        = number

  validation {
    condition     = var.instance_count > 0
    error_message = "instance_count must be greater than 0"
  }
}

variable "instance_type" {
  description = "Type of instance to create"
  type        = string
  default     = "t3a.medium"

  validation {
    condition     = can(regex("t3a\\.(nano|micro|small|medium|large|xlarge|2xlarge|3xlarge|metal)", var.instance_type))
    error_message = "instance_type must be a valid t3a instance type"
  }
}

variable "ami" {
  description = "AMI to use for the instance"
  type        = string

  validation {
    condition     = can(regex("ami-[a-f0-9]{17}", var.ami))
    error_message = "ami must be a valid AMI ID"
  }
}

variable "key_name" {
  description = "Name of the key pair to use for the instance"
  type        = string
}

variable "iam_instance_profile" {
  description = "Name of the IAM instance profile to use for the instance"
  type        = string
  default     = "fCCSSMInstanceProfileRole"
}

variable "subnets" {
  description = "Subnet objects to use for the instance"
  type = list(object({
    id         = string
    cidr_block = string
  }))
}

variable "security_group_ids" {
  description = "Security group IDs to use for the instance"
  type        = list(string)
}

variable "hostNum_start" {
  description = "Starting host number for consul servers"
  type        = number

  validation {
    condition     = var.hostNum_start > 0
    error_message = "hostNum_start must be greater than or equal to 0"
  }
}

variable "user_data_replace_on_change" {
  type        = bool
  description = "Recreate instances on changes to UserData"
  default     = false
}

variable "stack_tags" {
  description = "Tags to apply to the instance"
  type        = map(string)
  default     = {}
}

variable "zone" {
  description = "Cloudflare Zone to use for the instance"
  type = object({
    name = string
    id   = string
  })

  validation {
    condition     = can(regex("^[a-z0-9]{32}$", var.zone.id))
    error_message = "zone.id must be a valid Cloudflare Zone ID"
  }

  validation {
    condition     = length(var.zone.name) > 0
    error_message = "zone.name must be a non-empty string"
  }
}

variable "create_dns_records__private" {
  description = "Create DNS records for the private IP addresses of the instances"
  type        = bool
  default     = true
}
