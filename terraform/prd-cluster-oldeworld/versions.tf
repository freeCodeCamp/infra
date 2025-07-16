terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.0.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.109.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.7.1"
    }
  }
  required_version = ">= 1"
}
