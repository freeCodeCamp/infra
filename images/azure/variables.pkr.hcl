variable "az_sp_client_id" {
  type      = string
  default   = "${env("AZURE_SERVICE_PRINCIPAL_CLIENT_ID")}"
  sensitive = true
}

variable "az_sp_client_secret" {
  type      = string
  default   = "${env("AZURE_SERVICE_PRINCIPAL_CLIENT_SECRET")}"
  sensitive = true
}

variable "az_sp_tenant_id" {
  type      = string
  default   = "${env("AZURE_SERVICE_PRINCIPAL_TENANT_ID")}"
  sensitive = true
}

variable "az_subscription_id" {
  type      = string
  default   = "${env("AZURE_SUBSCRIPTION_ID")}"
  sensitive = true
}