terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.17.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.84.1"
    }
  }
  required_version = ">= 1"
}
