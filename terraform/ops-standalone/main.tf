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

data "hcp_packer_artifact" "linode_ubuntu" {
  bucket_name  = "linode-ubuntu"
  channel_name = "golden"
  platform     = "linode"
  region       = "us-east"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}

data "linode_instances" "stg_oldeworld_jms" {
  filter {
    name   = "tags"
    values = ["stg_oldeworld_jms"]
  }
}

data "linode_instances" "prd_oldeworld_jms" {
  filter {
    name   = "tags"
    values = ["prd_oldeworld_jms"]
  }
}
