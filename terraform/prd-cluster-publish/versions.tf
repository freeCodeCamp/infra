terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.7.1"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.69.0"
    }

    akamai = {
      source  = "akamai/akamai"
      version = "5.2.0"
    }
  }
  required_version = ">= 1"
}
