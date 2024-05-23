terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.50.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.90.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.33.0"
    }
  }
  required_version = ">= 1"
}
