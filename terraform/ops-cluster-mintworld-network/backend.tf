terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-ops-mintworld-network"
    }
  }
}
