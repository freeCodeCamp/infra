terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.7.2"
    }

    hcp = {
      source  = "hashicorp/hcp"
      version = "0.72.0"
    }

    akamai = {
      source  = "akamai/akamai"
      version = "5.3.0"
    }
  }
  required_version = ">= 1"
}
