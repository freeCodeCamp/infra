# Add output declarations here
output "list_of_nomad_servers__private_ips" {
  value = [for i in aws_instance.stg_mintworld_nomad_svr : i.private_ip]
}

output "list_of_consul_servers__private_ips" {
  value = [for i in aws_instance.stg_mintworld_consul_svr : i.private_ip]
}

output "list_of_cluster_workers__private_ips" {
  value = [for i in aws_instance.stg_mintworld_cluster_wkr : i.private_ip]
}
