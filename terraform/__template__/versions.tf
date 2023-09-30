terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.8.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.69.0"
    }
  }
  required_version = ">= 1"
}
