terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-prd-oldeworld--origins"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_nodebalancer" "prd_oldeworld_nb_pxy_1" {
  region = var.region
  label  = "prd-nb-oldeworld-pxy-1"
  tags   = ["prd", "oldeworld", "nb_pxy"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_1_config__port_80" {
  nodebalancer_id = linode_nodebalancer.prd_oldeworld_nb_pxy_1.id
  port            = 80
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}

resource "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_1_config__port_443" {
  nodebalancer_id = linode_nodebalancer.prd_oldeworld_nb_pxy_1.id
  port            = 443
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}

resource "linode_nodebalancer" "prd_oldeworld_nb_pxy_2" {
  region = var.region
  label  = "prd-nb-oldeworld-pxy-2"
  tags   = ["prd", "oldeworld", "nb_pxy"] # Value should use '_' as sepratator for compatibility with Ansible Dynamic Inventory
}

resource "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_2_config__port_80" {
  nodebalancer_id = linode_nodebalancer.prd_oldeworld_nb_pxy_2.id
  port            = 80
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}

resource "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_2_config__port_443" {
  nodebalancer_id = linode_nodebalancer.prd_oldeworld_nb_pxy_2.id
  port            = 443
  protocol        = "tcp"
  algorithm       = "leastconn"
  check           = "connection"
  check_interval  = 10
  check_timeout   = 5
  check_attempts  = 3
}
