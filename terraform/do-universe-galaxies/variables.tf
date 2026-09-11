variable "vpc_cidr" {
  description = "Source CIDR for the intra-VPC k3s rules."
  type        = string
  default     = "10.110.0.0/20"
}

variable "galaxy_tags" {
  description = "Droplet tags this firewall binds to. Membership is per-galaxy."
  type        = list(string)
  default = [
    "gxy-cassiopeia-k3s",
    "gxy-launchbase-k3s",
    "gxy-management-k3s",
    "gxy-static-k3s",
  ]
}
