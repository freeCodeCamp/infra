terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.3.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.109.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.4"
    }
  }
  required_version = ">= 1"
}
