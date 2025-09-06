terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.1.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.109.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.2"
    }
  }
  required_version = ">= 1"
}
