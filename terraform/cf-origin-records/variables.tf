variable "state_passphrase" {
  description = "State and plan passphrase (TF_VAR_state_passphrase, vultr/.env.enc, 1Password)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.state_passphrase) >= 32
    error_message = "state_passphrase must have 32 characters or more. Load vultr/.env.enc."
  }
}

variable "zone_ids" {
  description = "Cloudflare zone IDs by environment (TF_VAR_zone_ids, cloudflare/.env.enc)."
  type        = object({ stg = string, prd = string })
}

variable "linode_origin_ips" {
  description = "Linode NodeBalancer addresses by environment, first address first (TF_VAR_linode_origin_ips, cloudflare/.env.enc). A one-record hostname uses the first address."
  type        = object({ stg = list(string), prd = list(string) })

  validation {
    condition     = length(var.linode_origin_ips.stg) == 1 && length(var.linode_origin_ips.prd) == 3
    error_message = "linode_origin_ips needs 1 staging address and 3 production addresses."
  }
}
