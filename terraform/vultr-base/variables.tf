variable "state_passphrase" {
  description = "State and plan passphrase (TF_VAR_state_passphrase, vultr/.env.enc, 1Password)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "state_passphrase must have 32 characters or more. Load vultr/.env.enc."
  }
}

variable "region" {
  type    = string
  default = "ewr"
}

variable "vpc_cidr" {
  description = "Private VPC range of the Vultr fleet. Set it with TF_VAR_vpc_cidr from the sops envelope."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be an IPv4 CIDR."
  }
}

variable "ssh_public_keys" {
  description = "Team keys by name, for the Vultr account and the freecodecamp user."
  type        = map(string)
  default = {
    "ssh-camperbot-ed25519"     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIw0UuD62899Lqpf/+TLwJmWUq0iIs+7mXfjSHFBd+wO"
    "ssh-raisedadead-ed25519-1" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJZmuLl4e2SPr0V6eX5/hwh/B/Ve7+5nM69qYAWDVC7U"
    "ssh-raisedadead-ed25519-2" = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE2PjmTZnhALYZaEqn4z5/1NH2foqA6LRdTY98r8NBSU"
  }
}
