terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.59.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.7.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.109.0"
    }
  }
  required_version = ">= 1"
}
