variable "linode_token" {
  description = "The Linode API Personal Access Token."
}

variable "password" {
  description = "The root password for the Linode instances."
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

variable "userdata" {
  description = "The userdata to be used in provisioning the instances"
  default     = "I2Nsb3VkLWNvbmZpZwp1c2VyczoKICAtIG5hbWU6IGZyZWVjb2RlY2FtcAogICAgZ3JvdXBzOiBzdWRvCiAgICBzaGVsbDogIC9iaW4vYmFzaAogICAgc3VkbzogWydBTEw9KEFMTCkgTk9QQVNTV0Q6QUxMJ10KICAgIHNzaF9pbXBvcnRfaWQ6CiAgICAgIC0gZ2g6Y2FtcGVyYm90CiAgICAgIC0gcmFpc2VkYWRlYWQKcnVuY21kOgogIC0gdXNlcm1vZCAtYUcgZG9ja2VyIGZyZWVjb2RlY2FtcApmaW5hbF9tZXNzYWdlOiAnU2V0dXAgY29tcGxldGUnCg=="
}
