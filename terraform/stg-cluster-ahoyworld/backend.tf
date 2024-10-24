terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-stg-ahoyworld"
      project = "DigitalOcean"
    }
  }
}
