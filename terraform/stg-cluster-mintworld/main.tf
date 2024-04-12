locals {
  zone = "freecodecamp.net"
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

locals {
  count_svr_consul = 3
  count_svr_nomad  = 3
  count_wkr_nomad  = 5
}

# Private IPAM
locals {
  # Define the host number starting serial of hosts:
  hostNum_start_svr_consul = 30 # Consul servers
  hostNum_start_svr_nomad  = 40 # Nomad servers
  hostNum_start_wkr_nomad  = 50 # Nomad workers
}

locals {
  # Define the CIDR prefix ranges for subnets:
  # Needing 6 subnets, 3 private and 3 public,
  subnet_cidr_prefixes = cidrsubnets(
    "10.0.0.0/16",

    4, # "10.0.0.0/20" - Private Subnet - Availability Zone 1
    4, # "10.0.16.0/20" - Private Subnet - Availability Zone 2
    4, # "10.0.32.0/20" - Private Subnet - Availability Zone 3

    4, # "10.0.48.0/20" - Public Subnet - Availability Zone 1
    4, # "10.0.64.0/20" - Public Subnet - Availability Zone 2
    4  # "10.0.80.0/20" - Public Subnet - Availability Zone 3
  )
}

module "stg_mw_network" {
  source = "./modules/network"

  region                                 = var.region
  network_env                            = "stg"
  subnet_cidr_prefixes                   = local.subnet_cidr_prefixes
  enable_eip_on_launch_in_public_subnets = false
  stack_tags                             = var.stack_tags
}

module "stg_mw_consul_svr" {
  source = "./modules/instances"

  instance_count       = local.count_svr_consul
  instance_env         = "stg"
  instance_prefix      = "consul-svr"
  instance_type        = "t3a.medium"
  hostNum_start        = local.hostNum_start_svr_consul
  ami                  = data.hcp_packer_artifact.aws_ami.external_identifier
  key_name             = data.aws_key_pair.stg_ssh_service_user_key.key_name
  iam_instance_profile = data.aws_iam_instance_profile.stg_mw_instance_profile.name
  security_group_ids   = [module.stg_mw_network.out__sg_id]
  subnets              = module.stg_mw_network.out__subnets.private
  zone                 = local.zone
  stack_tags           = var.stack_tags
}

module "stg_mw_nomad_svr" {
  source = "./modules/instances"

  instance_count       = local.count_svr_nomad
  instance_env         = "stg"
  instance_prefix      = "nomad-svr"
  instance_type        = "t3a.medium"
  hostNum_start        = local.hostNum_start_svr_nomad
  ami                  = data.hcp_packer_artifact.aws_ami.external_identifier
  key_name             = data.aws_key_pair.stg_ssh_service_user_key.key_name
  iam_instance_profile = data.aws_iam_instance_profile.stg_mw_instance_profile.name
  security_group_ids   = [module.stg_mw_network.out__sg_id]
  subnets              = module.stg_mw_network.out__subnets.private
  zone                 = local.zone
  stack_tags           = var.stack_tags
}

module "stg_mw_nomad_wkr" {
  source = "./modules/instances"

  instance_count       = local.count_wkr_nomad
  instance_env         = "stg"
  instance_prefix      = "nomad-wkr"
  instance_type        = "t3a.medium"
  hostNum_start        = local.hostNum_start_wkr_nomad
  ami                  = data.hcp_packer_artifact.aws_ami.external_identifier
  key_name             = data.aws_key_pair.stg_ssh_service_user_key.key_name
  iam_instance_profile = data.aws_iam_instance_profile.stg_mw_instance_profile.name
  security_group_ids   = [module.stg_mw_network.out__sg_id]
  subnets              = module.stg_mw_network.out__subnets.private
  zone                 = local.zone
  stack_tags           = var.stack_tags
}
