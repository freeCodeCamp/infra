terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.31.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.101.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.50.0"
    }
  }
  required_version = ">= 1"
}
