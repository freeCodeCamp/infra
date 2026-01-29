terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.6.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.5"
    }
  }
  required_version = ">= 1.8"
}
