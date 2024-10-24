resource "digitalocean_vpc" "stg_vpc" {
  name        = "stg-ahoyworld-vpc"
  region      = "nyc3"
  description = "Staging VPC for AhoyWorld"
  ip_range    = "10.0.8.0/22"
}

resource "digitalocean_firewall" "stg_fw_internal" {
  name = "stg-ahoyworld-fw-internal"

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
      digitalocean_vpc.stg_vpc.ip_range
    ]
  }
}

resource "digitalocean_firewall" "stg_fw_external" {
  name = "stg-ahoyworld-fw-external"

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
