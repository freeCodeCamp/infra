variable "cloudflare_account_id" {
  description = "Cloudflare account id owning the R2 bucket"
  type        = string
}

variable "bucket_name" {
  description = "R2 bucket holding all Universe static-app deploys"
  type        = string
  default     = "universe-static-apps-01"
}

variable "bucket_location" {
  description = "R2 jurisdiction (WEUR / ENAM / WNAM / APAC / OC / AUTO)"
  type        = string
  default     = "WEUR"
}

variable "deploy_retention_days" {
  description = "Age threshold for archive sweep of per-deploy prefixes; matches the archive-sweep policy (see prior dossier 2026-05-11-archive-sweep-ga-hardening)."
  type        = number
  default     = 90
}

variable "abort_incomplete_uploads_days" {
  description = "Age threshold for cleaning up incomplete multipart uploads"
  type        = number
  default     = 7
}
