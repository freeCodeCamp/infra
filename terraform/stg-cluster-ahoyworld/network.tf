resource "digitalocean_vpc" "stg_vpc" {
  name        = "stg-ahoyworld-vpc"
  region      = "nyc3"
  description = "Staging VPC for AhoyWorld"
  ip_range    = "10.0.8.0/22"
}

resource "digitalocean_firewall" "stg_fw_internal" {
  name = "stg-ahoyworld-fw-internal"

  droplet_ids = flatten([
    [for instance in digitalocean_droplet.stg_ahoyworld_clt : instance.id],
    digitalocean_droplet.stg_ahoyworld_api[*].id,
    [for instance in digitalocean_droplet.stg_ahoyworld_nws : instance.id],
    digitalocean_droplet.stg_ahoyworld_jms[*].id,
  ])

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

  outbound_rule {
    protocol   = "tcp"
    port_range = "1-65535"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  depends_on = [
    digitalocean_droplet.stg_ahoyworld_clt,
    digitalocean_droplet.stg_ahoyworld_api,
    digitalocean_droplet.stg_ahoyworld_nws,
    digitalocean_droplet.stg_ahoyworld_jms,
  ]
}

resource "digitalocean_firewall" "stg_fw_external" {
  name = "stg-ahoyworld-fw-external"

  droplet_ids = flatten([
    digitalocean_droplet.stg_ahoyworld_pxy[*].id
  ])

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

  outbound_rule {
    protocol   = "tcp"
    port_range = "1-65535"
    destination_addresses = [
      "0.0.0.0/0",
      "::/0",
    ]
  }

  depends_on = [
    digitalocean_droplet.stg_ahoyworld_pxy,
  ]
}
