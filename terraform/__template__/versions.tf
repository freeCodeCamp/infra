terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.22.0"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.91.0"
    }
  }
  required_version = ">= 1"
}
