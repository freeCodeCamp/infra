# This data source depends on the stackscript resource
# which is created in terraform/ops-stackscripts/main.tf
data "linode_stackscripts" "cloudinit_scripts" {
  filter {
    name   = "label"
    values = ["CloudInit"]
  }
}

# This data source depends on the domain resource
# which is created in terraform/ops-dns/main.tf
data "linode_domain" "ops_dns_domain" {
  domain = "freecodecamp.net"
}

data "hcp_packer_image" "linode_ubuntu" {
  bucket_name    = "linode-ubuntu"
  channel        = "latest"
  cloud_provider = "linode"
  region         = "us-east"
}

locals {
  pxy_node_count = 3
  api_node_count = 3
  clt_node_count = 2
}

locals {
  clteng_node_count = local.clt_node_count
  cltchn_node_count = local.clt_node_count
  cltcnt_node_count = local.clt_node_count
  cltesp_node_count = local.clt_node_count
  cltger_node_count = local.clt_node_count
  cltita_node_count = local.clt_node_count
  cltjpn_node_count = local.clt_node_count
  cltpor_node_count = local.clt_node_count
  cltukr_node_count = local.clt_node_count
}

locals {
  ipam_block_nginx   = 10 # 10.0.0.11, 10.0.0.12, ...
  ipam_block_api     = 20
  ipam_block_cltchn  = 30 # 10.0.0.31, 10.0.0.32, ...
  ipam_block_cltcnt  = 35 # 10.0.0.36, 10.0.0.37, ...
  ipam_block_clteng  = 40
  ipam_block_cltesp  = 45
  ipam_block_cltger  = 50
  ipam_block_cltita  = 55
  ipam_block_cltjpn  = 60
  ipam_block_cltpor  = 65
  ipam_block_cltukr  = 70
  ipam_block_newstst = 150
}
