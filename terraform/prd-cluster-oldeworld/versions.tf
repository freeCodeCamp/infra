terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.23.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.94.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.36.0"
    }
  }
  required_version = ">= 1"
}
