resource "linode_firewall" "stg_oldeworld_firewall_pxy" {
  label = "stg-fw-oldeworld-pxy"

  inbound {
    label    = "allow-ssh_from-anywhere"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "allow-http_from-nb"
    ports    = "80"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["192.168.255.0/24"]
  }

  inbound {
    label    = "allow-https_from-nb"
    ports    = "443"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["192.168.255.0/24"]
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    [for i in linode_instance.stg_oldeworld_pxy : i.id]
  ])
}

resource "linode_firewall" "stg_oldeworld_firewall" {
  label = "stg-fw-oldeworld"

  inbound {
    label    = "allow-ssh_from-anywhere"
    ports    = "22"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    # All API nodes.
    [for i in linode_instance.stg_oldeworld_api : i.id],

    # All Client nodes.
    [for i in linode_instance.stg_oldeworld_clteng : i.id],
    [for i in linode_instance.stg_oldeworld_cltchn : i.id],
    [for i in linode_instance.stg_oldeworld_cltcnt : i.id],
    [for i in linode_instance.stg_oldeworld_cltesp : i.id],
    [for i in linode_instance.stg_oldeworld_cltger : i.id],
    [for i in linode_instance.stg_oldeworld_cltita : i.id],
    [for i in linode_instance.stg_oldeworld_cltjpn : i.id],
    [for i in linode_instance.stg_oldeworld_cltpor : i.id],
    [for i in linode_instance.stg_oldeworld_cltukr : i.id],

    # News Test node.
    linode_instance.stg_oldeworld_newstst.id
  ])
}
