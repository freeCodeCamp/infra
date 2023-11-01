terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.4"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.76.0"
    }
  }
  required_version = ">= 1"
}
