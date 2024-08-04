variable "aws_access_key_id" {
  description = "The value of the AWS Access Key ID."
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "The value of the AWS Secret Access Key."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "The name of the region in which to deploy instances."
  default     = "us-east-1"
  type        = string
}
