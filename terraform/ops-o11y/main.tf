locals {
  prefix  = "ops-vm-o11y-k3s"
  tag     = "ops-o11y"
  project = "o11y"

  nodes = {
    for i in range(var.node_count) :
    format("%02d", i + 1) => "${local.prefix}-${var.region}-${format("%02d", i + 1)}"
  }
}

data "digitalocean_ssh_key" "ops_o11y" {
  for_each = toset(var.ssh_key_names)
  name     = each.value
}

data "digitalocean_project" "o11y" {
  name = local.project
}

resource "digitalocean_tag" "ops_o11y" {
  name = local.tag
}

resource "digitalocean_droplet" "ops_o11y" {
  for_each = local.nodes

  name   = each.value
  region = var.region
  size   = var.size
  image  = var.image
  tags   = ["ops", digitalocean_tag.ops_o11y.id]

  ssh_keys  = [for key in data.digitalocean_ssh_key.ops_o11y : key.id]
  user_data = file("${path.root}/../../cloud-init/basic.yml")

  lifecycle {
    ignore_changes = [image, ssh_keys, user_data]
  }
}

moved {
  from = digitalocean_droplet.ops_o11y
  to   = digitalocean_droplet.ops_o11y["01"]
}

resource "digitalocean_firewall" "ops_o11y" {
  name = local.tag
  tags = [digitalocean_tag.ops_o11y.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  dynamic "inbound_rule" {
    for_each = {
      "tcp/6443"      = { protocol = "tcp", port_range = "6443" }
      "tcp/2379-2380" = { protocol = "tcp", port_range = "2379-2380" }
      "tcp/10250"     = { protocol = "tcp", port_range = "10250" }
      "udp/8472"      = { protocol = "udp", port_range = "8472" }
    }
    content {
      protocol    = inbound_rule.value.protocol
      port_range  = inbound_rule.value.port_range
      source_tags = [digitalocean_tag.ops_o11y.id]
    }
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

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
}

resource "digitalocean_project_resources" "ops_o11y" {
  project   = data.digitalocean_project.o11y.id
  resources = [for node in digitalocean_droplet.ops_o11y : node.urn]
}
