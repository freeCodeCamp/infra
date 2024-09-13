terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.67.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.95.1"
    }

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.5"
    }

    random = {
      source  = "hashicorp/random"
      version = "3.6.3"
    }

    tailscale = {
      source  = "tailscale/tailscale"
      version = "0.16.2"
    }
  }
  required_version = ">= 1"
}
