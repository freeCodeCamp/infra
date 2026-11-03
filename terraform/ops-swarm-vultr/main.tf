module "fleet" {
  source = "../modules/vultr-fleet"

  nodes = {
    "ops-vm-swarm-mgr-1" = { role = "swarm-mgr", plan = "vc2-2c-4gb", firewall_group = "vultr-base" }
  }
  snapshot_id   = var.snapshot_id
  ssh_key_names = var.ssh_key_names
}
