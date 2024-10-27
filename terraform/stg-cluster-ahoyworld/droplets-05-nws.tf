resource "digitalocean_droplet" "stg_ahoyworld_nws" {
  for_each = { for i in local.nws_instances : i.name => i }

  name = "stg-vm-ahoyworld-nws-${each.value.name}"
  tags = ["stg", "ahoyworld", "nws", "stg_ahoyworld_nws", "${each.value.name}"]

  image    = data.hcp_packer_artifact.do_ubuntu.external_identifier
  size     = "s-2vcpu-4gb"
  region   = "nyc3"
  vpc_uuid = digitalocean_vpc.stg_vpc.id

  ssh_keys = [for ssh_key in data.digitalocean_ssh_key.stg_ssh_keys : ssh_key.id]

  user_data = templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
    tf_fqdn     = "nws-${each.value.name}.ahoyworld.stg.${local.zone}"
    tf_hostname = "nws-stg-${each.value.name}"
  })
}

resource "cloudflare_record" "stg_ahoyworld_nws_dns__public" {
  for_each = { for i in local.nws_instances : i.name => i }

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "nws-${each.value.name}.ahoyworld.stg.${var.network_subdomain}"
  content = digitalocean_droplet.stg_ahoyworld_nws[each.key].ipv4_address
}

resource "cloudflare_record" "stg_ahoyworld_nws_dns__private" {
  for_each = { for i in local.nws_instances : i.name => i }

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "nws-${each.value.name}.ahoyworld.stg"
  content = digitalocean_droplet.stg_ahoyworld_nws[each.key].ipv4_address_private
}
