terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.61.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.2"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.6.2"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.16.1"
    }
  }
  required_version = ">= 1"
}
