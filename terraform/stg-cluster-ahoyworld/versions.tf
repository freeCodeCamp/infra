terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.53.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.106.0"
    }
  }
  required_version = ">= 1"
}
