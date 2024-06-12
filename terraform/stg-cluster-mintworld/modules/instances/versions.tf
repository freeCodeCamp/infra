terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.53.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.35.0"
    }
  }
  required_version = ">= 1"
}
