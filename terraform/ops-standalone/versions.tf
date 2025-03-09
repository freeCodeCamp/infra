terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.34.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.102.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.1.0"
    }
  }
  required_version = ">= 1"
}
