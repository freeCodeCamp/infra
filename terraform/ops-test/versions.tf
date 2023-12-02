terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.7"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.77.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.20.0"
    }
  }
  required_version = ">= 1"
}
