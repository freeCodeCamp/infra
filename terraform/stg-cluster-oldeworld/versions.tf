terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.36.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.102.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.0"
    }
  }
  required_version = ">= 1"
}
