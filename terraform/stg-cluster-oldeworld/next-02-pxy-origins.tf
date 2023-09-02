data "linode_nodebalancer" "stg_oldeworld_nb_pxy" {
  id = 388830 # TODO: Find a way to get this ID dynamically
}

data "linode_nodebalancer_config" "stg_oldeworld_nb_pxy_config__port_443" {
  id              = 597405 # TODO: Find a way to get this ID dynamically
  nodebalancer_id = data.linode_nodebalancer.stg_oldeworld_nb_pxy.id
}

data "linode_nodebalancer_config" "stg_oldeworld_nb_pxy_config__port_80" {
  id              = 597404 # TODO: Find a way to get this ID dynamically
  nodebalancer_id = data.linode_nodebalancer.stg_oldeworld_nb_pxy.id
}

resource "linode_nodebalancer_node" "stg_oldeworld_nb_pxy_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancer.stg_oldeworld_nb_pxy.id
  config_id       = data.linode_nodebalancer_config.stg_oldeworld_nb_pxy_config__port_443.id
  address         = "${linode_instance.stg_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "stg-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "stg_oldeworld_nb_pxy_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancer.stg_oldeworld_nb_pxy.id
  config_id       = data.linode_nodebalancer_config.stg_oldeworld_nb_pxy_config__port_80.id
  address         = "${linode_instance.stg_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "stg-node-pxy-80-${count.index}"
}

resource "akamai_dns_record" "stg_oldeworld_nb_pxy_dnsrecord__public" {
  zone       = local.zone
  recordtype = "A"
  ttl        = 120

  name   = "oldeworld.stg.${var.network_subdomain}.${local.zone}"
  target = [data.linode_nodebalancer.stg_oldeworld_nb_pxy.ipv4]
}
