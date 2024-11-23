terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.44.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.46.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.99.0"
    }
  }
  required_version = ">= 1"
}
