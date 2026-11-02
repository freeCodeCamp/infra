module "fleet" {
  source = "../modules/vultr-fleet"

  nodes = {
    for n in range(1, 4) : "ops-vm-o11y-${n}" => {
      role           = "o11y"
      plan           = "vc2-6c-16gb"
      firewall_group = "vultr-base"
    }
  }
  snapshot_id   = var.snapshot_id
  ssh_key_names = var.ssh_key_names
}
