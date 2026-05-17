terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "do-universe-galaxies"
      project = "universe-platform"
    }
  }
}
