output "ops_staffwiki_key_ACCESS_KEY" {
  sensitive = true
  value     = linode_object_storage_key.ops_staffwiki_key.access_key
}

output "ops_staffwiki_key_SECRET_KEY" {
  sensitive = true
  value     = linode_object_storage_key.ops_staffwiki_key.secret_key
}
