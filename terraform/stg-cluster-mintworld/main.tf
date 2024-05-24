locals {
  zone = "freecodecamp.net"
}

data "cloudflare_zone" "cf_zone" {
  name = local.zone
}

data "hcp_packer_artifact" "aws_ami" {
  bucket_name  = "aws-nomad-consul"
  channel_name = "golden"
  platform     = "aws"
  region       = var.region
}

data "aws_key_pair" "stg_ssh_service_user_key" {
  include_public_key = true

  filter {
    name   = "fingerprint"
    values = ["83/jBIfPmZ0tkwonWcUgwo0smIhxwYWaGOZvr2tpz0E="]
  }
}

data "aws_iam_instance_profile" "stg_mw_instance_profile" {
  name = "fCCSSMInstanceProfileRole"
}

data "aws_vpc" "ops_mw_vpc" {
  filter {
    name   = "tag:Name"
    values = ["ops-mw-vpc"]
  }
}

