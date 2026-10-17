terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.105.0"
    }
  }
  required_version = "~> 1.12"
}
