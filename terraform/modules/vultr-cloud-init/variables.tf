variable "hostname" {
  description = "OS hostname; the caller passes the Vultr label."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.hostname))
    error_message = "hostname must be one DNS label: lowercase letters, digits and hyphens."
  }
}

variable "ssh_authorized_keys" {
  description = "Public keys for the freecodecamp user."
  type        = list(string)

  validation {
    condition     = length(var.ssh_authorized_keys) > 0
    error_message = "ssh_authorized_keys must hold at least one key."
  }
}
