module "lambdas" {
  source = "philips-labs/github-runner/aws//modules/download-lambda"
  lambdas = [
    {
      name = "webhook"
      tag  = var.tag_version
    },
    {
      name = "runners"
      tag  = var.tag_version
    },
    {
      name = "runner-binaries-syncer"
      tag  = var.tag_version
    }
  ]
}

output "files" {
  value = module.lambdas.files
}
