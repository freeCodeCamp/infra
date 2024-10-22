resource "digitalocean_vpc" "prd_vpc" {
  name        = "prd-ahoyworld-vpc"
  region      = "nyc3"
  description = "Production VPC for AhoyWorld"
  ip_range    = "10.0.0.0/20"
}

resource "digitalocean_firewall" "prd_fw_internal" {
  name = "prd-ahoyworld-fw-internal"

  inbound_rule {
    protocol   = "tcp"
    port_range = "22"
    source_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  inbound_rule {
    protocol   = "tcp"
    port_range = "1-65535"
    source_addresses = [
      digitalocean_vpc.prd_vpc.ip_range
    ]
  }
}

resource "digitalocean_firewall" "prd_fw_external" {
  name = "prd-ahoyworld-fw-external"

  inbound_rule {
    protocol   = "tcp"
    port_range = "22"
    source_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  inbound_rule {
    protocol   = "tcp"
    port_range = "80"
    source_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  inbound_rule {
    protocol   = "tcp"
    port_range = "443"
    source_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }
}
