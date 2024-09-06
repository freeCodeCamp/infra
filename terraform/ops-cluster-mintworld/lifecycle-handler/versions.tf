terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.66.0"
    }
    github = {
      source  = "integrations/github"
      version = "6.2.3"
    }
  }
  required_version = ">= 1"
}
