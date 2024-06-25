terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.55.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.93.0"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.35.0"
    }
  }
  required_version = ">= 1"
}
