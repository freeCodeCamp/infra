terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.59.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.82.0"
    }
  }
  required_version = ">= 1"
}
