terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.20.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.90.0"
    }
  }
  required_version = ">= 1"
}
