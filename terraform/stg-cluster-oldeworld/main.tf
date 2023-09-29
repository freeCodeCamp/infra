locals {
  zone = "freecodecamp.net"
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

data "linode_instances" "ops_standalone_backoffice" {
  filter {
    name = "label"
    values = [
      "ops-vm-backoffice",
    ]
  }
}

locals {
  pxy_node_count = 3 # number of proxy nodes
  api_node_count = 3 # number of api nodes
  clt_node_count = 2 # number of client nodes for EACH LANGUAGE!
  jms_node_count = 3 # number of JAMStack nodes
}

locals {
  ipam_block_pxy = 10  # 10.0.0.11, 10.0.0.12, ...
  ipam_block_api = 20  # 10.0.0.21, 10.0.0.22, ...
  ipam_block_clt = 40  # 10.0.0.41, 10.0.0.42, ...
  ipam_block_nws = 100 # 10.0.0.100, 10.0.0.102, ...
  ipam_block_jms = 120 # 10.0.0.120, 10.0.0.121, ...
}

// When removing an item, DO NOT change the IPAM number.
locals {
  nws_instances = {
    eng = { name = "eng", ipam_id = 0 }, # 10.0.0.100
    # chn = { name = "chn", ipam_id = 1 }, # 10.0.0.101
    # esp = { name = "esp", ipam_id = 2 }, # ...
    # ita = { name = "ita", ipam_id = 3 },
    # jpn = { name = "jpn", ipam_id = 4 },
    # kor = { name = "kor", ipam_id = 5 },
    # por = { name = "por", ipam_id = 6 },
    # ukr = { name = "ukr", ipam_id = 7 },
    # ger = { name = "ger", ipam_id = 8 }
  }

  clt_config_meta = {
    eng = { name = "eng", ipam_id = 0, node_count = local.clt_node_count },  # 10.0.0.40, 10.0.0.41, ...
    chn = { name = "chn", ipam_id = 5, node_count = local.clt_node_count },  # 10.0.0.45, 10.0.0.46, ...
    esp = { name = "esp", ipam_id = 10, node_count = local.clt_node_count }, # 10.0.0.50, 10.0.0.51, ...
    ita = { name = "ita", ipam_id = 15, node_count = local.clt_node_count }, # 10.0.0.55, 10.0.0.56, ...
    jpn = { name = "jpn", ipam_id = 20, node_count = local.clt_node_count }, # 10.0.0.60, 10.0.0.61, ...
    # kor = { name = "kor", ipam_id = 6, node_count = local.clt_node_count },
    por = { name = "por", ipam_id = 25, node_count = local.clt_node_count }, # 10.0.0.65, 10.0.0.66, ...
    ukr = { name = "ukr", ipam_id = 30, node_count = local.clt_node_count }, # 10.0.0.70, 10.0.0.71, ...
    ger = { name = "ger", ipam_id = 35, node_count = local.clt_node_count }, # 10.0.0.75, 10.0.0.76, ...
    cnt = { name = "cnt", ipam_id = 40, node_count = local.clt_node_count }  # 10.0.0.80, 10.0.0.81, ...
    swa = { name = "swa", ipam_id = 45, node_count = local.clt_node_count }  # 10.0.0.85, 10.0.0.86, ...
  }

  clt_instances = flatten([
    [for k, v in local.clt_config_meta : [
      for i in range(v.node_count) : {
        name     = v.name
        ipam_id  = v.ipam_id + i
        instance = "${k}-${i}"
      }
    ]],
  ])
}
