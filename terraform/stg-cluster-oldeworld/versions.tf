terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.27.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.95.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.40.0"
    }
  }
  required_version = ">= 1"
}
