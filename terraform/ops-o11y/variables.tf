variable "region" {
  type    = string
  default = "fra1"
}

variable "size" {
  type    = string
  default = "s-4vcpu-8gb-amd"
}

variable "image" {
  type    = string
  default = "ubuntu-24-04-x64"
}

variable "ssh_key_names" {
  type    = list(string)
  default = ["ssh-camperbot-ed25519", "ssh-raisedadead-ed25519"]
}
