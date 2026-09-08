variable "region" {
  type    = string
  default = "fra1"
}

variable "size" {
  type    = string
  default = "s-4vcpu-16gb-amd"
}

variable "image" {
  type    = string
  default = "ubuntu-24-04-x64"
}

variable "ssh_key_names" {
  type    = list(string)
  default = ["ssh-camperbot-ed25519", "ssh-raisedadead-ed25519"]
}

variable "node_count" {
  type    = number
  default = 3

  validation {
    condition     = var.node_count >= 1 && floor(var.node_count) == var.node_count
    error_message = "node_count must be a whole number of at least 1."
  }
}
