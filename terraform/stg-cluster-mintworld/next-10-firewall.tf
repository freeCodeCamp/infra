resource "linode_firewall" "stg_mintworld_firewall" {
  label = "stg-fw-mintworld-svr"

  inbound {
    label    = "allow-ssh_from-anywhere"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-all-tcp_from-vlan"
    ports    = "1-65535"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4 = flatten([
      ["10.0.0.0/8"]
    ])
  }

  inbound {
    label    = "allow-all-udp_from-vlan"
    ports    = "1-65535"
    protocol = "UDP"
    action   = "ACCEPT"
    ipv4 = flatten([
      ["10.0.0.0/8"]
    ])
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    [for i in linode_instance.stg_mintworld_nomad_svr : i.id],
    [for i in linode_instance.stg_mintworld_consul_svr : i.id],
    [for i in linode_instance.stg_mintworld_cluster_wkr : i.id],
  ])
}
