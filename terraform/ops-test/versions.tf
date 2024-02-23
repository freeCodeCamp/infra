terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.15.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.83.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.25.0"
    }
  }
  required_version = ">= 1"
}
