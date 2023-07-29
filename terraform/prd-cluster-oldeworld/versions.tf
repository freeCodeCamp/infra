terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.5.2"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.67.0"
    }
  }
  required_version = ">= 1"
}
