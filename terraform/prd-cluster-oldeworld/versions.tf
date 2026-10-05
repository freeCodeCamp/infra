terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.6.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.110.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.9"
    }
  }
  required_version = ">= 1"
}
