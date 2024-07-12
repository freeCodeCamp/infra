terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-workers-stateless"
      project = "AWS-PrimaryCloud"
    }
  }
}
