locals {
  prefix = "ops-mwcp"
}

// This enables SSM access + Cloud Auto-join, and should be pre-existing,
// ensure that the role is created in the account.
data "aws_iam_instance_profile" "instance_profile" {
  name = "fCCEC2InstanceProfileRole"
}

// Ensure instance type is valid
data "aws_ec2_instance_type" "instance_type" {
  instance_type = var.instance_type
}

data "hcp_packer_artifact" "aws_ami" {
  bucket_name  = "aws-nomad-consul"
  channel_name = "golden"
  platform     = "aws"
  region       = var.region
}

data "aws_key_pair" "ssh_service_user_key" {
  include_public_key = true
  filter {
    name   = "fingerprint"
    values = ["83/jBIfPmZ0tkwonWcUgwo0smIhxwYWaGOZvr2tpz0E="]
  }
}

data "aws_vpc" "vpc" {
  tags = {
    Name = "ops-mw-vpc"
  }
}

data "aws_subnets" "subnets_prv" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Type  = "Private"
    Stack = "mintworld"
  }
}
