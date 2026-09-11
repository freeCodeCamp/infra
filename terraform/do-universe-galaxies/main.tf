locals {
  # docs.k3s.io/installation/requirements#networking, plus Cilium health
  # (4240) and hubble-peer (4244), plus 4443 for the metrics-server
  # hostNetwork patch in ansible/play-k3s--bootstrap.yml.
  vpc_tcp_ports = ["2379", "2380", "4240", "4244", "4443", "5001", "6443", "10250"]
}

resource "digitalocean_firewall" "gxy_fra1" {
  name = "gxy-fw-fra1"
  tags = var.galaxy_tags

  dynamic "inbound_rule" {
    for_each = toset(["22", "80", "443"])
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = ["0.0.0.0/0"]
    }
  }

  dynamic "inbound_rule" {
    for_each = toset(local.vpc_tcp_ports)
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = [var.vpc_cidr]
    }
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "8472"
    source_addresses = [var.vpc_cidr]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0"]
  }

  dynamic "outbound_rule" {
    for_each = toset(["tcp", "udp"])
    content {
      protocol              = outbound_rule.value
      port_range            = "1-65535"
      destination_addresses = ["0.0.0.0/0"]
    }
  }
}
