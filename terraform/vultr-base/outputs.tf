output "vpc_id" {
  value = vultr_vpc.base.id
}

output "vpc_description" {
  value = vultr_vpc.base.description
}

output "firewall_group_ids" {
  value = local.firewall_group_ids
}

output "ssh_key_ids" {
  value = { for name, key in vultr_ssh_key.team : name => key.id }
}
