provider "linode" {
  token = var.linode_token
}

provider "hcp" {
  client_id     = var.hcp_client_id
  client_secret = var.hcp_client_secret
  project_id    = "377fca8e-97bb-4058-ae1b-2845bac3c6bc" # ops
}
