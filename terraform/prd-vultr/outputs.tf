output "nodes" {
  value = module.fleet.nodes
}

output "ts_machine_name_prefix" {
  description = "TS_MACHINE_NAME_PREFIX for the production client deploy (T33)."
  value       = "${local.env}-vm-clt"
}
