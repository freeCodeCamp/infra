terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.56.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.36.0"
    }
  }
  required_version = ">= 1"
}
