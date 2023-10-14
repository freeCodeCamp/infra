provider "linode" {
  token = var.linode_token
}

provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

provider "akamai" {
  edgerc         = ".edgerc"
  config_section = "default"
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
