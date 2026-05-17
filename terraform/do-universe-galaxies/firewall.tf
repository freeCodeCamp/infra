# One DO cloud-firewall per galaxy. Rule set targets a k3s ingress
# topology where the CF edge reaches the droplet on 80/443, the
# operator reaches it on 22 (from `var.operator_ssh_cidrs`), and
# everything else is closed. Cilium / k3s intra-cluster traffic is
# carried over the VPC private network — DO cloud firewalls don't
# inspect VPC-internal traffic, so no internal allow-rules are
# needed.
#
# HTTP/HTTPS inbound is narrowed to the published Cloudflare edge
# CIDRs (`var.cf_edge_cidrs_v4` + `_v6`). This is the only path that
# enforces CF-as-mandatory-proxy: without it, anyone with the droplet
# IP can hit the origin on plain HTTP and bypass the CF WAF (the
# `freecode.camp` zone is Flexible-SSL — CF→origin is plain HTTP).
# Operator MUST refresh the CF CIDR variables when CF publishes a
# new range (https://www.cloudflare.com/ips-v4 + ips-v6); quarterly
# cadence is the documented expectation.
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

  # Inbound: HTTP/HTTPS from CF edge CIDRs only. Empty `cf_edge_cidrs_v4`
  # collapses to no rule — the operator is on the hook to refresh the
  # list (CF publishes at https://www.cloudflare.com/ips-v4 +
  # /ips-v6). Empty list means HTTP/HTTPS is closed entirely; safer
  # than world-open default.
  dynamic "inbound_rule" {
    for_each = length(concat(var.cf_edge_cidrs_v4, var.cf_edge_cidrs_v6)) > 0 ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "80"
      source_addresses = concat(var.cf_edge_cidrs_v4, var.cf_edge_cidrs_v6)
    }
  }

  dynamic "inbound_rule" {
    for_each = length(concat(var.cf_edge_cidrs_v4, var.cf_edge_cidrs_v6)) > 0 ? [1] : []
    content {
      protocol         = "tcp"
      port_range       = "443"
      source_addresses = concat(var.cf_edge_cidrs_v4, var.cf_edge_cidrs_v6)
    }
  }

  # Inbound: ICMP from operator CIDRs only — no world-open echo. Drops
  # outside-of-CF host enumeration. Smokeping / monitoring must run
  # from a known operator CIDR or via in-cluster probes (kube-state-
  # metrics + traefik metrics already cover liveness).
  dynamic "inbound_rule" {
    for_each = length(var.operator_ssh_cidrs) > 0 ? [1] : []
    content {
      protocol         = "icmp"
      source_addresses = var.operator_ssh_cidrs
    }
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

  # IaC absorb: live firewall is imported via `imports.sh`. Genuine
  # destroy requires editing this block out first.
  lifecycle {
    prevent_destroy = true
  }
}
