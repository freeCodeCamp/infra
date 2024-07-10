terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-workers"
      project = "AWS-PrimaryCloud"
    }
  }
}
