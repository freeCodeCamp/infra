resource "digitalocean_droplet" "stg_ahoyworld_jms" {
  count = local.jms_node_count
  name  = "stg-vm-ahoyworld-jms-${count.index + 1}"
  tags  = ["stg", "ahoyworld", "jms", "stg_ahoyworld_jms"]

  image    = data.hcp_packer_artifact.do_ubuntu.external_identifier
  size     = "s-2vcpu-4gb"
  region   = "nyc3"
  vpc_uuid = digitalocean_vpc.stg_vpc.id

  ssh_keys = [for ssh_key in data.digitalocean_ssh_key.stg_ssh_keys : ssh_key.id]

  user_data = templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
    tf_fqdn     = "jms-${count.index + 1}.ahoyworld.stg.${local.zone}"
    tf_hostname = "jms-stg-${count.index + 1}"
  })
}

resource "cloudflare_record" "stg_ahoyworld_jms_dns__public" {
  count = local.jms_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "jms-${count.index + 1}.ahoyworld.stg.${var.network_subdomain}"
  content = digitalocean_droplet.stg_ahoyworld_jms[count.index].ipv4_address
}

resource "cloudflare_record" "stg_ahoyworld_jms_dns__private" {
  count = local.jms_node_count

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "jms-${count.index + 1}.ahoyworld.stg"
  content = digitalocean_droplet.stg_ahoyworld_jms[count.index].ipv4_address_private
}
