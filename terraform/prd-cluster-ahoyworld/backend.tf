terraform {
  backend "s3" {
    bucket       = "fcc-infra-state"
    key          = "prd-cluster-ahoyworld/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
