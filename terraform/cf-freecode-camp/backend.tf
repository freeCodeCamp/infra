terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "cf-freecode-camp"
      project = "universe-platform"
    }
  }
}
