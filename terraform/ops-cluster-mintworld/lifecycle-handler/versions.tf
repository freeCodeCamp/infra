terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.69.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.3.0"
    }
  }
  required_version = ">= 1"
}
