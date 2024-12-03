terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.45.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.47.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.99.0"
    }
  }
  required_version = ">= 1"
}
