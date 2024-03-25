terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.42.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.84.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.26.0"
    }
  }
  required_version = ">= 1"
}
