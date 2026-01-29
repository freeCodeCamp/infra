# OpenTofu S3 Backend Configuration
#
# Prerequisites:
# 1. AWS S3 bucket: fcc-infra-state (with versioning enabled)
# 2. AWS credentials configured (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#
# State is encrypted server-side (SSE-S3) and uses native S3 locking.
# Backup replication to Cloudflare R2 is handled via S3 event notifications + Lambda.

terraform {
  backend "s3" {
    bucket       = "fcc-infra-state"
    key          = "<@@workspace@@>/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
