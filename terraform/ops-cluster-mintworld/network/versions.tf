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

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.41.0"
    }
  }
  required_version = ">= 1"
}
