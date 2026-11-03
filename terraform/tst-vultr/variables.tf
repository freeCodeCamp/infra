variable "state_passphrase" {
  description = "State and plan passphrase (TF_VAR_state_passphrase, vultr/.env.enc, 1Password)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "state_passphrase must have 32 characters or more. Load vultr/.env.enc."
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

variable "plan" {
  type    = string
  default = "vc2-2c-4gb"
}

variable "ssh_key_names" {
  description = "Names of the vultr-base team keys."
  type        = list(string)
  default = [
    "ssh-camperbot-ed25519",
    "ssh-raisedadead-ed25519-1",
    "ssh-raisedadead-ed25519-2",
  ]
}
