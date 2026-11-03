output "user_data" {
  value = "#cloud-config\n${yamlencode(local.cloud_config)}"
}
