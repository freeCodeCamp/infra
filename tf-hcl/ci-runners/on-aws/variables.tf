
variable "github_app_key_base64" {
  description = "base64 encoded private key of the GitHub App"
}

variable "github_app_id" {
  description = "value of the GitHub App ID"
}

variable "aws_profile" {
  default     = "default"
  description = "AWS profile name of the IAM user to use for Terraform"
}

variable "aws_region" {
  default     = "us-east-1"
  description = "AWS region to use for Terraform"
}

variable "environment" {
  default     = "ubuntu"
  description = "Environment name to use for tagging resources"
}

variable "runner_os" {
  type    = string
  default = "linux"
}

variable "ami_name_filter" {
  type    = string
  default = "github-runner-amzn2-x86_64-*"
}
