terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-workers-web"
      project = "AWS-PrimaryCloud"
    }
  }
}
