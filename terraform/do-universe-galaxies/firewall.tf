# One DO cloud-firewall per galaxy. Rule set targets a k3s ingress
# topology where the edge (CF) reaches the droplet on 80/443, the
# operator reaches it on 22 (from `var.operator_ssh_cidrs`), and
# everything else is closed. Cilium / k3s intra-cluster traffic is
# carried over the VPC private network — DO cloud firewalls don't
# inspect VPC-internal traffic, so no internal allow-rules are
# needed.
resource "digitalocean_firewall" "this" {
  for_each = var.galaxies

  name = "fw-${each.key}"
  tags = [each.value.tags[0]]

  # Inbound: SSH from operator CIDRs only.
  dynamic "inbound_rule" {
    for_each = length(var.operator_ssh_cidrs) > 0 ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "22"
      source_addresses = var.operator_ssh_cidrs
    }
  }

  # Inbound: HTTP/HTTPS from the world (CF proxied, but the edge
  # is allowed to use any IP per the CF IP range; pin to CF ranges
  # via var.operator_ssh_cidrs override if locking down further).
  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Inbound: ICMP from the world (lets monitoring + smokeping reach).
  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  # Outbound: full egress. k3s pulls images from registries +
  # artemis pushes to R2 — locking egress here breaks deploys.
  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
