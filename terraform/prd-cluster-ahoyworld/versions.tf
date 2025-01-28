terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.47.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.51.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.102.0"
    }
  }
  required_version = ">= 1"
}
