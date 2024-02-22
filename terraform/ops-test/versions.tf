terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.14.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.25.0"
    }
  }
  required_version = ">= 1"
}
