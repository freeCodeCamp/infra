terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.30.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.97.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.45.0"
    }
  }
  required_version = ">= 1"
}
