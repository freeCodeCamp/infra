locals {
  zone = "freecodecamp.net"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}

# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInitfreeCodeCamp"]
  }
  filter {
    name   = "is_public"
    values = ["false"]
  }
}

data "hcp_packer_image" "linode_ubuntu" {
  bucket_name    = "linode-ubuntu"
  channel        = "golden"
  cloud_provider = "linode"
  region         = "us-east"
}

locals {
  consul_svr_count  = 3
  nomad_svr_count   = 3
  cluster_wkr_count = 5
}

locals {
  ipam_block_consul_svr  = 10 # 10.0.0.11, 10.0.0.12, ...
  ipam_block_nomad_svr   = 30 # 10.0.0.31, 10.0.0.32, ...
  ipam_block_cluster_wkr = 50 # 10.0.0.51, 10.0.0.52, ...
}
