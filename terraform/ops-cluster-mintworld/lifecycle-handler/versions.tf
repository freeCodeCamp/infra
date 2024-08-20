terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.63.1"
    }
    github = {
      source  = "integrations/github"
      version = "6.2.3"
    }
  }
  required_version = ">= 1"
}
