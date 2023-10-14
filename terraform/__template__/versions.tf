terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.9.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.73.0"
    }
  }
  required_version = ">= 1"
}
