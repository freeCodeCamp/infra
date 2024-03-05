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
  count_svr_consul = 3
  count_svr_nomad  = 3
  count_wkr_nomad  = 5
}

# Private IPAM
locals {
  # Define the host number starting serial of hosts:
  hostNum_start_svr_consul = 30 # Consul servers
  hostNum_start_svr_nomad  = 40 # Nomad servers
  hostNum_start_wkr_nomad  = 50 # Nomad workers
}

locals {
  # Define the CIDR prefix ranges for subnets:
  # Needing 6 subnets, 3 private and 3 public,
  subnet_cidr_prefixes = cidrsubnets(
    "10.0.0.0/16",

    4, # "10.0.0.0/20" - Private Subnet - Availability Zone 1
    4, # "10.0.16.0/20" - Private Subnet - Availability Zone 2
    4, # "10.0.32.0/20" - Private Subnet - Availability Zone 3

    4, # "10.0.48.0/20" - Public Subnet - Availability Zone 1
    4, # "10.0.64.0/20" - Public Subnet - Availability Zone 2
    4  # "10.0.80.0/20" - Public Subnet - Availability Zone 3
  )
}
