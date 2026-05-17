terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "cf-r2-universe-static"
      project = "universe-platform"
    }
  }
}
