terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.8.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.69.0"
    }

    akamai = {
      source  = "akamai/akamai"
      version = "5.2.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
  required_version = ">= 1"
}
