
resource "random_id" "random" {
  byte_length = 20
}
module "runners" {
  source                          = "philips-labs/github-runner/aws"
  version                         = "1.17.0"
  create_service_linked_role_spot = true
  aws_region                      = var.aws_region
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnets

  prefix = var.environment
  tags = {
    Project     = "GitHubRunner"
    Environment = var.environment
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
  runner_extra_labels         = "ubuntu,on-aws"

  # enable access to the runners via SSM
  enable_ssm_on_runners = true

  minimum_running_time_in_minutes = 60

  # idle_config = [{
  #   # https://github.com/philips-labs/terraform-aws-github-runner#supported-config-
  #   # This is different from AWS Cron Expressions.
  #   cron      = "* * * * * *"
  #   timeZone  = "UTC"
  #   idleCount = 2
  # }]

  instance_types = ["m5.large", "c5.large"]

  # override delay of events in seconds
  delay_webhook_event   = 5
  runners_maximum_count = 10

  # set up a fifo queue to remain order
  fifo_build_queue = true

  # override scaling down
  # scale_down_schedule_expression = "cron(* * * * ? *)"

  # More on AWS Cron Expressions: https://stackoverflow.com/a/39508593/1932901
  # Will scale down to minimum runners if there are no builds in the queue in the last 2 hours
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
