terraform {
  backend "s3" {
    bucket       = "fcc-infra-state"
    key          = "stg-cluster-ahoyworld/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
