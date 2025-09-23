terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.67.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.52.5"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.110.0"
    }
  }
  required_version = ">= 1"
}
