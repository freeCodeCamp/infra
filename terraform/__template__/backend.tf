terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "<@@template@@>"
      project = "<@@template@@>"
    }
  }
}
