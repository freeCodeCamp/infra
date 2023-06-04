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
#
resource "linode_domain" "freecodecamp_net" {
  domain    = "freecodecamp.net"
  type      = "master"
  soa_email = "dev@freecodecamp.org"
}

resource "linode_domain_record" "dmarc" {
  domain_id   = linode_domain.freecodecamp_net.id
  name        = "_dmarc"
  record_type = "TXT"
  target      = "v=DMARC1;p=reject;sp=reject;adkim=s;aspf=s"
}

resource "linode_domain_record" "spf" {
  domain_id   = linode_domain.freecodecamp_net.id
  name        = linode_domain.freecodecamp_net.domain
  record_type = "TXT"
  target      = "v=spf1 -all"
}

resource "linode_domain_record" "dkim" {
  domain_id   = linode_domain.freecodecamp_net.id
  name        = "*._domainkey"
  record_type = "TXT"
  target      = "v=DKIM1; p="
}
# DO NOT DELETE OR MODIFY THIS RESOURCE --------
