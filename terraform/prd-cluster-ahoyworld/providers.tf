provider "digitalocean" {
  token = var.do_token
}

provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
