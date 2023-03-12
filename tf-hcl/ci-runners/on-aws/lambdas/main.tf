module "lambdas" {
  source = "github.com/philips-labs/terraform-aws-github-runner//modules/download-lambda"
  lambdas = [
    {
      name = "webhook"
      tag  = var.download_lambda_tag
    },
    {
      name = "runners"
      tag  = var.download_lambda_tag
    },
    {
      name = "runner-binaries-syncer"
      tag  = var.download_lambda_tag
    }
  ]
}

output "files" {
  value = module.lambdas.files
}
