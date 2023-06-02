terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-ops-dns"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_domain" "freecodecamp_net" {
  domain    = "freecodecamp.net"
  type      = "master"
  soa_email = "dev@freecodecamp.org"
}
