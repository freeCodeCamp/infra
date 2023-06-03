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

# DO NOT DELETE OR MODIFY THIS RESOURCE --------
#
# This resource is a Domain resource that may have records
# outside of this module or even outside of Terraform.
resource "linode_domain" "freecodecamp_net" {
  domain    = "freecodecamp.net"
  type      = "master"
  soa_email = "dev@freecodecamp.org"
}
# DO NOT DELETE OR MODIFY THIS RESOURCE --------

resource "linode_domain_record" "local" {
  domain_id   = linode_domain.freecodecamp_net.id
  name        = "local"
  record_type = "A"
  target      = "127.0.0.1"

  ttl_sec = 3600
}
