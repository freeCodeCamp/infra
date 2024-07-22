// This enables SSM access + Cloud Auto-join, and should be pre-existing,
// ensure that the role is created in the account.
data "aws_iam_instance_profile" "instance_profile" {
  name = "fCCEC2InstanceProfileRole"
}

// Ensure instance type is valid
data "aws_ec2_instance_type" "instance_type" {
  instance_type = var.instance_type
}

data "aws_ec2_instance_type" "instance_type_prv_routers" {
  instance_type = var.instance_type_prv_routers
}

data "hcp_packer_artifact" "aws_ami" {
  bucket_name  = "aws-nomad-consul"
  channel_name = "latest"
  platform     = "aws"
  region       = var.region
}

data "hcp_packer_artifact" "aws_ami_prv_routers" {
  bucket_name  = "aws-ubuntu"
  channel_name = "latest"
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
    Name = "ops-mwnet-vpc"
  }
}

data "aws_security_groups" "sg_main" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  filter {
    name   = "group-name"
    values = ["ops-mwnet-sg"]
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

data "aws_subnets" "subnets_pub" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Type  = "Public"
    Stack = "mintworld"
  }
}

data "cloudflare_zone" "cf_zone" {
  name = "freecodecamp.net"
}

locals {
  prefix               = "ops-mwctl"
  cloudflare_subdomain = "cp.mintworld"

  // WARNING: This key is used in scripts.
  datacenter                 = "mintworld"
  consul_cloud_auto_join_key = "ops-mintworld-01"
  // WARNING: This key is used in scripts.
}
