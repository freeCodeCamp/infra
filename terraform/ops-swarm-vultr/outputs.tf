output "nodes" {
  value = module.fleet.nodes
}

output "ts_machine_name" {
  description = "TS_MACHINE_NAME for the api deploy (T33): the Swarm manager."
  value       = one(keys(module.fleet.nodes))
}
