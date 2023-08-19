terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.6.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.68.0"
    }
  }
  required_version = ">= 1"
}
