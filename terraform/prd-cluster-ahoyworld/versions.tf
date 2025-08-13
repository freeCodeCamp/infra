terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.64.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.109.0"
    }
  }
  required_version = ">= 1"
}
