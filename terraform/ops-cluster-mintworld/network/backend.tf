terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-mintworld-network"
      project = "AWS-PrimaryCloud"
    }
  }
}
