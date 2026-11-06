variable "stg_step" {
  description = "Staging step: linode, 50 or 100. Change the default, then plan and apply."
  type        = string
  default     = "linode"

  validation {
    condition     = contains(["linode", "50", "100"], var.stg_step)
    error_message = "stg_step must be linode, 50 or 100. Staging has one Linode record for each hostname, so it has no 25 step."
  }
}

variable "proxies_down" {
  description = "Names of Vultr proxies that must get no traffic, such as prd-vm-pxy-2. Change the default, then plan and apply."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for name in var.proxies_down : can(regex("^(stg|prd)-vm-pxy-[0-9]+$", name))])
    error_message = "Each name in proxies_down must be a proxy name, such as prd-vm-pxy-2."
  }
}

variable "prd_step" {
  description = "Production step: linode, 25, 50 or 100. Change the default, then plan and apply."
  type        = string
  default     = "linode"

  validation {
    condition     = contains(["linode", "25", "50", "100"], var.prd_step)
    error_message = "prd_step must be linode, 25, 50 or 100."
  }
}
