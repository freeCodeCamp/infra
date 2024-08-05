terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.61.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.94.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.38.0"
    }
  }
  required_version = ">= 1"
}
