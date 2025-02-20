resource "digitalocean_droplet" "stg_ahoyworld_clt" {
  for_each = { for i in local.clt_instances : i.instance => i }

  name = "stg-vm-ahoyworld-clt-${each.value.instance}"
  tags = ["stg", "ahoyworld", digitalocean_tag.stg_tag_fw_internal.id, "clt", "stg_ahoyworld_clt", "${each.value.name}"]

  image    = data.hcp_packer_artifact.do_ubuntu.external_identifier
  size     = "s-2vcpu-4gb"
  region   = "nyc3"
  vpc_uuid = digitalocean_vpc.stg_vpc.id

  ssh_keys = [for ssh_key in data.digitalocean_ssh_key.stg_ssh_keys : ssh_key.id]

  user_data = templatefile("${path.root}/cloud-init--userdata.yml.tftpl", {
    tf_fqdn     = "clt-${each.value.instance}.ahoyworld.stg.${local.zone}"
    tf_hostname = "clt-stg-${each.value.instance}"
  })
}

resource "cloudflare_record" "stg_ahoyworld_clt_dns__public" {
  for_each = { for i in local.clt_instances : i.instance => i }

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "clt-${each.value.instance}.ahoyworld.stg.${var.network_subdomain}"
  content = digitalocean_droplet.stg_ahoyworld_clt[each.key].ipv4_address
}

resource "cloudflare_record" "stg_ahoyworld_clt_dns__private" {
  for_each = { for i in local.clt_instances : i.instance => i }

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name    = "clt-${each.value.instance}.ahoyworld.stg"
  content = digitalocean_droplet.stg_ahoyworld_clt[each.key].ipv4_address_private
}
