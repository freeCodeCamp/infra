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
  ipam_block_pxy = 10  # 10.0.0.11, 10.0.0.12, ...
  ipam_block_api = 20  # 10.0.0.21, 10.0.0.22, ...
  ipam_block_clt = 40  # 10.0.0.41, 10.0.0.42, ...
  ipam_block_nws = 100 # 10.0.0.100, 10.0.0.102, ...
}

// When removing an item, DO NOT change the IPAM number.
locals {
  nws_instances = {
    eng = { name = "eng", ipam_id = 1 }, # 10.0.0.101
    chn = { name = "chn", ipam_id = 2 }, # 10.0.0.102
    esp = { name = "esp", ipam_id = 3 }, # ...
    ita = { name = "ita", ipam_id = 4 },
    jpn = { name = "jpn", ipam_id = 5 },
    kor = { name = "kor", ipam_id = 6 },
    por = { name = "por", ipam_id = 7 },
    ukr = { name = "ukr", ipam_id = 8 },
    # ger = { name = "ger", ipam_id = 9 }
  }

  clt_config_meta = {
    eng = { name = "eng", ipam_id = 0, node_count = local.clt_node_count },
    chn = { name = "chn", ipam_id = 1, node_count = local.clt_node_count },
    esp = { name = "esp", ipam_id = 2, node_count = local.clt_node_count },
    ita = { name = "ita", ipam_id = 3, node_count = local.clt_node_count },
    jpn = { name = "jpn", ipam_id = 4, node_count = local.clt_node_count },
    # kor = { name = "kor", ipam_id = 5, node_count = local.clt_node_count },
    por = { name = "por", ipam_id = 6, node_count = local.clt_node_count },
    ukr = { name = "ukr", ipam_id = 7, node_count = local.clt_node_count },
    ger = { name = "ger", ipam_id = 8, node_count = local.clt_node_count }
  }

  clt_instances = flatten([
    [for k, v in local.clt_config_meta : [
      for i in range(v.node_count) : {
        name     = v.name
        ipam_id  = v.ipam_id + 1
        instance = "${k}-${i}"
      }
    ]],
  ])
}
