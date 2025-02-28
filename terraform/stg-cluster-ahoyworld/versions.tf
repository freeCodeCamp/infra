terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.49.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.104.0"
    }
  }
  required_version = ">= 1"
}
