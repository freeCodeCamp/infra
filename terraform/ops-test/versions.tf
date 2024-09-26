terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.29.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.96.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.42.0"
    }
  }
  required_version = ">= 1"
}
