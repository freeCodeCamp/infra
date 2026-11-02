output "nodes" {
  value = {
    for name, node in vultr_instance.tst : name => {
      id      = node.id
      label   = node.label
      role    = local.nodes[name].role
      main_ip = node.main_ip
    }
  }
}

output "vpc_cidr" {
  value = "${data.vultr_vpc.base.v4_subnet}/${data.vultr_vpc.base.v4_subnet_mask}"
}

output "team_keys" {
  value = local.team_keys
}
