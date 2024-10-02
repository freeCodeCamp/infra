terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.69.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.96.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.43.0"
    }
  }
  required_version = ">= 1"
}
