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

data "aws_lb" "internal_lb" {
  name = "ops-mwnet-prv-lb"
}
locals {
  prefix = "ops-mwweb"
  infix  = "nmd-web"

  nomad_web_instance_type = data.aws_ec2_instance_type.instance_type.id
  nomad_web_count_min     = 3
  nomad_web_count_max     = 5

  // WARNING: These are used in scripts - DO NOT CHANGE
  datacenter                 = "mintworld"
  consul_cloud_auto_join_key = "ops-mintworld-01"
  aws_tag__role_nomad        = "nmd-clt"
  cluster_tag__client_role   = "web"
  // WARNING: These are used in scripts - DO NOT CHANGE
}
