terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.62.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.94.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.39.0"
    }
  }
  required_version = ">= 1"
}
