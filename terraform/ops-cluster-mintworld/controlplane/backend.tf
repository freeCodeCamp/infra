terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-controlplane"
      project = "AWS-PrimaryCloud"
    }
  }
}
