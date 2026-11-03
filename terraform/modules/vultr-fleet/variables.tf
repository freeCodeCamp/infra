variable "nodes" {
  description = "VMs by name (<env>-vm-<role>-<n>): role, Vultr plan, vultr-base firewall group."
  type = map(object({
    role           = string
    plan           = string
    firewall_group = string
  }))

  validation {
    condition     = alltrue([for name, _ in var.nodes : can(regex("^[a-z0-9]+-vm-[a-z0-9-]+-[0-9]+$", name))])
    error_message = "Each node name must match <env>-vm-<role>-<n>."
  }

  validation {
    condition     = alltrue([for node in var.nodes : contains(["vultr-base", "vultr-pxy"], node.firewall_group)])
    error_message = "firewall_group must be vultr-base or vultr-pxy."
  }
}

variable "snapshot_id" {
  description = "Vultr snapshot ID from the image build."
  type        = string
}

variable "region" {
  type    = string
  default = "ewr"
}

variable "ssh_key_names" {
  description = "Names of the vultr-base team keys."
  type        = list(string)
}
