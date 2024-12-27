terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.46.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.49.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.101.0"
    }
  }
  required_version = ">= 1"
}
