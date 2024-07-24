terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.59.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.16.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.38.0"
    }
  }
  required_version = ">= 1"
}
