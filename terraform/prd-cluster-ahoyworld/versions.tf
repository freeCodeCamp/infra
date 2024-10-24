terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.43.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.44.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.97.0"
    }
  }
  required_version = ">= 1"
}
