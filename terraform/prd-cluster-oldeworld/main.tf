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
  ipam_block_nginx  = 10 # 10.0.0.11, 10.0.0.12, ...
  ipam_block_api    = 20
  ipam_block_cltchn = 30 # 10.0.0.31, 10.0.0.32, ...
  ipam_block_cltcnt = 35 # 10.0.0.36, 10.0.0.37, ...
  ipam_block_clteng = 40
  ipam_block_cltesp = 45
  ipam_block_cltger = 50
  ipam_block_cltita = 55
  ipam_block_cltjpn = 60
  ipam_block_cltpor = 65
  ipam_block_cltukr = 70
  ipam_block_news   = 150
}

// When removing an item, DO NOT change the IPAM number.
locals {
  ghost_instances = {
    eng = { name = "eng", ipam_id = 1 },
    chn = { name = "chn", ipam_id = 2 },
    esp = { name = "esp", ipam_id = 3 },
    ita = { name = "ita", ipam_id = 4 },
    jpn = { name = "jpn", ipam_id = 5 },
    kor = { name = "kor", ipam_id = 6 },
    por = { name = "por", ipam_id = 7 },
    ukr = { name = "ukr", ipam_id = 8 }
  }
}
