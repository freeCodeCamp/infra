terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.72.2"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1"
}
