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

# Looks up the latest custom Ubuntu image built by Packer
# Images are named: ami-ubuntu-22.04-YYYYMMDD.hhmm
data "linode_images" "ubuntu" {
  filter {
    name   = "label"
    values = ["ami-ubuntu-22.04-*"]
  }
  filter {
    name   = "is_public"
    values = ["false"]
  }
}

locals {
  # Get the most recently created image (sorted by created date descending)
  linode_ubuntu_image = sort([for img in data.linode_images.ubuntu.images : img.id])[length(data.linode_images.ubuntu.images) - 1]
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

data "linode_instances" "stg_oldeworld_api" {
  filter {
    name   = "tags"
    values = ["stg_oldeworld_api", "new"]
  }
}

data "linode_instances" "prd_oldeworld_api" {
  filter {
    name   = "tags"
    values = ["prd_oldeworld_api", "new"]
  }
}
