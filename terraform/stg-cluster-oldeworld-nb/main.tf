terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-stg-oldeworld--origins"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_nodebalancer" "stg_oldeworld_nb_pxy" {
  region = var.region
  label  = "stg-nb-oldeworld-pxy"
  tags   = ["stg", "oldeworld", "nb_pxy"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_nodebalancer_config" "stg_oldeworld_nb_pxy_config__port_80" {
  nodebalancer_id = linode_nodebalancer.stg_oldeworld_nb_pxy.id
  port            = 80
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}

resource "linode_nodebalancer_config" "stg_oldeworld_nb_pxy_config__port_443" {
  nodebalancer_id = linode_nodebalancer.stg_oldeworld_nb_pxy.id
  port            = 443
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}
