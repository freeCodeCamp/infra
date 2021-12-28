locals {
  environment = "default"
  aws_region  = "us-east-1"
}

resource "random_id" "random" {
  byte_length = 20
}

module "runners" {
  source                          = "philips-labs/github-runner/aws"
  create_service_linked_role_spot = true
  aws_region                      = local.aws_region
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  environment = local.environment
  tags = {
    Project = "GitHubRunners"
  }

  github_app = {
    key_base64     = var.github_app_key_base64
    id             = var.github_app_id
    webhook_secret = random_id.random.hex
  }

  # Grab zip files via lambda_download
  webhook_lambda_zip                = "lambdas/webhook.zip"
  runner_binaries_syncer_lambda_zip = "lambdas/runner-binaries-syncer.zip"
  runners_lambda_zip                = "lambdas/runners.zip"

  enable_organization_runners = false
  runner_extra_labels         = "on-aws,self-hosted,ubuntu"

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  userdata_template = "./templates/user-data.sh"
  ami_owners        = ["099720109477"] # Canonical's Amazon account ID

  ami_filter = {
    name = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  block_device_mappings = {
    # Set the block device name for Ubuntu root device
    device_name = "/dev/sda1"
  }

  runner_log_files = [
    {
      "log_group_name" : "syslog",
      "prefix_log_group" : true,
      "file_path" : "/var/log/syslog",
      "log_stream_name" : "{instance_id}"
    },
    {
      "log_group_name" : "user_data",
      "prefix_log_group" : true,
      "file_path" : "/var/log/user-data.log",
      "log_stream_name" : "{instance_id}/user_data"
    },
    {
      "log_group_name" : "runner",
      "prefix_log_group" : true,
      "file_path" : "/home/runners/actions-runner/_diag/Runner_**.log",
      "log_stream_name" : "{instance_id}/runner"
    }
  ]
  # Make these many idle runners available for use all the time
  idle_config = [{
    cron      = "* * * * * *"
    timeZone  = "UTC"
    idleCount = 1
  }]

  # Let the module manage the service linked role - Required when the Actor/Operator deploying this doesn't have sufficient IAM permissions
  # create_service_linked_role_spot = true

  instance_types = ["m5.large", "c5.large"]

  # override delay of events in seconds
  delay_webhook_event   = 5
  runners_maximum_count = 10

  # override scaling down - Will scale down to minimum runners if there are no builds in the queue in the last 2 hours
  # Also more context: https://stackoverflow.com/a/39508593/1932901
  scale_down_schedule_expression = "cron(0 0/2 * * ? *)"
}

terraform {
  cloud {
    organization = "freecodecamp"

    workspaces {
      name = "tfws-ops-github-runners"
    }
  }
}
