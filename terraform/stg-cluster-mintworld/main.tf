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
  consul_svr_count  = 3
  nomad_svr_count   = 3
  cluster_wkr_count = 5
}

locals {
  # Define the base IPs for the subnets - to be used for the CIDR blocks with prefix, ex. "10.0.64.0/18"
  subnet_base_ips = [
    "10.0.0.0",
    "10.0.64.0",
    "10.0.128.0"
  ]
  # Define the starting block for each type of server
  ip_start_block_nomad_svr   = 10
  ip_start_block_consul_svr  = 20
  ip_start_block_cluster_wkr = 30
}
