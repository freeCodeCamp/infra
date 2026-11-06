terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.9.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.115.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.10"
    }
  }
  required_version = ">= 1"
}
