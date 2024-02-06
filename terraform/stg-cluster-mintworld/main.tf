locals {
  zone = "freecodecamp.net"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}
data "hcp_packer_artifact" "aws_ubuntu" {
  bucket_name  = "aws-ubuntu"
  channel_name = "golden"
  platform     = "aws"
  region       = var.region
}

data "aws_key_pair" "stg_ssh_service_user_key" {
  include_public_key = true

  filter {
    name   = "fingerprint"
    values = ["83/jBIfPmZ0tkwonWcUgwo0smIhxwYWaGOZvr2tpz0E="]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  count_svr_consul  = 3
  count_svr_nomad   = 3
  count_wkr_cluster = 5
}

# Private IPAM
locals {
  # Define the base IPs for the subnets
  # to be used for the CIDR blocks with
  # prefix, ex. "10.0.64.0/18"
  subnet_base_ips = [
    "10.0.0.0",
    "10.0.64.0",
    "10.0.128.0"
  ]

  # ip_start_nlb_consul = 10 // L4 load balancer for consul
  # ip_start_nlb_nomad  = 20 // L4 load balancer for nomad

  ip_start_svr_consul  = 30 // Consul servers
  ip_start_svr_nomad   = 40 // Nomad servers
  ip_start_wkr_cluster = 50 // Nomad workers
}
