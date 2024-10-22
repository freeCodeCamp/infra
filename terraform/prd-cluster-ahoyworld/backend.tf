terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-prd-ahoyworld"
      project = "DigitalOcean"
    }
  }
}
