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

    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.4"
    }
  }
  required_version = ">= 1"
}
