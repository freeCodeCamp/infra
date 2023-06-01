variable "linode_token" {
  description = "The Linode API Personal Access Token."
}

variable "public_stackscript" {
  description = "Whether or not to make the StackScript public."
  default     = "false"
}
