output "nodes" {
  value = {
    for name, node in vultr_instance.this : name => {
      id      = node.id
      role    = var.nodes[name].role
      main_ip = node.main_ip
    }
  }
}
