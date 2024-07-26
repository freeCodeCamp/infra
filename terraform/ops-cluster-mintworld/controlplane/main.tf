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

data "aws_subnet" "all_subnets_details" {
  for_each = toset(concat(data.aws_subnets.subnets_prv.ids, data.aws_subnets.subnets_pub.ids))
  id       = each.value
}

data "aws_lb" "internal_lb" {
  name = "ops-mwnet-prv-lb"
}

locals {
  prefix = "ops-mwctl"

  consul_svr_instance_type = data.aws_ec2_instance_type.instance_type.id
  consul_svr_count_min     = 3
  consul_svr_count_max     = 5

  nomad_svr_instance_type = data.aws_ec2_instance_type.instance_type.id
  nomad_svr_count_min     = 3
  nomad_svr_count_max     = 5

  prv_routers_count_min = 1
  prv_routers_count_max = 3

  // WARNING: These are used in scripts - DO NOT CHANGE
  datacenter                 = "mintworld"
  consul_cloud_auto_join_key = "ops-mintworld-01"
  aws_tag__role_nomad        = "nomad-svr"
  aws_tag__role_consul       = "consul-svr"
  aws_tag__role_tailscale    = "prv-tsrouter"
  // WARNING: These are used in scripts - DO NOT CHANGE
}
