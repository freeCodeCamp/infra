terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-lifecycle-handler"
      project = "AWS-PrimaryCloud"
    }
  }
}
