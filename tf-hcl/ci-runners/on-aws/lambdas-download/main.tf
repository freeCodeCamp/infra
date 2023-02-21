locals {
  version = "v2.2.1"
}

module "lambdas" {
  source = "github.com/philips-labs/terraform-aws-github-runner//modules/download-lambda"
  lambdas = [
    {
      name = "webhook"
      tag  = local.version
    },
    {
      name = "runners"
      tag  = local.version
    },
    {
      name = "runner-binaries-syncer"
      tag  = local.version
    }
  ]
}

output "files" {
  value = module.lambdas.files
}
