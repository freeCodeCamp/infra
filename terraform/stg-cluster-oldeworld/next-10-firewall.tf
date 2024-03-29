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

  inbound {
    label    = "allow-all-tcp-from-private-ip"
    ports    = "1-65535"
    protocol = "TCP"
    action   = "ACCEPT"
    ipv4 = flatten([
      // Allow all ports from the backoffice instance private IP. Used for Docker Swarm management.
      ["${data.linode_instances.ops_standalone_backoffice.instances[0].private_ip_address}/32"],

      // Allow all ports from the private IP within the instance group. Used for Docker Swarm management.
      [for i in linode_instance.stg_oldeworld_jms : "${i.private_ip_address}/32"],
    ])
  }

  inbound {
    label    = "allow-all-udp-from-private-ip"
    ports    = "1-65535"
    protocol = "UDP"
    action   = "ACCEPT"
    ipv4 = flatten([
      // Allow all ports from the backoffice instance private IP. Used for Docker Swarm management.
      ["${data.linode_instances.ops_standalone_backoffice.instances[0].private_ip_address}/32"],

      // Allow all ports from the private IP within the instance group. Used for Docker Swarm management.
      [for i in linode_instance.stg_oldeworld_jms : "${i.private_ip_address}/32"],
    ])
  }

  # outbound { }

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  linodes = flatten([
    # All API nodes.
    [for i in linode_instance.stg_oldeworld_api : i.id],

    # All Client nodes.
    [for i in linode_instance.stg_oldeworld_clt : i.id],

    # All News Nodes.
    [for i in linode_instance.stg_oldeworld_nws : i.id],

    # All JMS Nodes.
    [for i in linode_instance.stg_oldeworld_jms : i.id],
  ])
}
