terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.65.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.95.1"
    }

    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "4.40.0"
    }
  }
  required_version = ">= 1"
}
