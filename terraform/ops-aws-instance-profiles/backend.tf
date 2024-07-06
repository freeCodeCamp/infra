terraform {
  cloud {
    organization = "freecodecamp"
    workspaces {
      name    = "tfws-ops-aws-instance-profiles"
      project = "AWS-PrimaryCloud"
    }
  }
}
