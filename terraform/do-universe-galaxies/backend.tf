terraform {
  backend "s3" {
    bucket = "infra-tfstate"
    key    = "do-universe-galaxies/terraform.tfstate"
    region = "auto"

    use_lockfile                = true
    use_path_style              = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
