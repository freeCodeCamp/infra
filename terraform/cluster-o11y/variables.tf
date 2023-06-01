variable "linode_token" {
  description = "The Linode API Personal Access Token."
}

variable "password" {
  description = "The root password for the Linode instances."
}

variable "import_ssh_users" {
  description = "The users to import their public keys to the Linode instances with ssh-import-id."
}

variable "worker_node_count" {
  description = "The number of worker instances to create."
  default     = 3
}

variable "leader_node_count" {
  description = "The number of leader instances to create."
  default     = 1
}

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east"
}

variable "image_id" {
  description = "The ID for the Linode image to be used in provisioning the instances"
  default     = "private/20418248"
}
