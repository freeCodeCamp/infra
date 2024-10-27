locals {
  zone = "freecodecamp.net"
}

data "hcp_packer_artifact" "do_ubuntu" {
  bucket_name  = "digitalocean-ubuntu"
  channel_name = "latest"
  platform     = "digitalocean"
  region       = "nyc3"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}

# data "linode_instances" "ops_standalone_backoffice" {
#   filter {
#     name = "label"
#     values = [
#       "ops-vm-backoffice",
#     ]
#   }
# }

locals {
  ssh_accounts = ["ssh-service-camperbot-ed25519", "ssh-service-terraform-ed25519"]
}

data "digitalocean_ssh_key" "stg_ssh_keys" {
  for_each = toset(local.ssh_accounts)
  name     = each.value
}

locals {
  pxy_node_count = 3 # number of proxy nodes
  api_node_count = 3 # number of api nodes
  clt_node_count = 2 # number of client nodes for EACH LANGUAGE!
  jms_node_count = 3 # number of JAMStack nodes
}

locals {
  nws_instances = {
    # eng = { name = "eng" }
    # i18n = { name = "i18n" }
  }

  clt_config_meta = {
    eng = { name = "eng", node_count = local.clt_node_count },
    chn = { name = "chn", node_count = local.clt_node_count },
    esp = { name = "esp", node_count = local.clt_node_count },
    ita = { name = "ita", node_count = local.clt_node_count },
    jpn = { name = "jpn", node_count = local.clt_node_count },
    # kor = { name = "kor", node_count = local.clt_node_count },
    por = { name = "por", node_count = local.clt_node_count },
    ukr = { name = "ukr", node_count = local.clt_node_count },
    ger = { name = "ger", node_count = local.clt_node_count },
    cnt = { name = "cnt", node_count = local.clt_node_count }
    swa = { name = "swa", node_count = local.clt_node_count }
  }

  clt_instances = flatten([
    [for k, v in local.clt_config_meta : [
      for i in range(v.node_count) : {
        name     = v.name
        instance = "${k}-${i}"
      }
    ]],
  ])
}
