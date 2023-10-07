terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.72.2"
    }
  }
  required_version = ">= 1"
}
