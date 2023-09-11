data "linode_nodebalancer" "prd_oldeworld_nb_pxy" {
  id = 389361 # TODO: Find a way to get this ID dynamically
}

data "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_config__port_443" {
  id              = 667462 # TODO: Find a way to get this ID dynamically
  nodebalancer_id = data.linode_nodebalancer.prd_oldeworld_nb_pxy.id
}

data "linode_nodebalancer_config" "prd_oldeworld_nb_pxy_config__port_80" {
  id              = 667461 # TODO: Find a way to get this ID dynamically
  nodebalancer_id = data.linode_nodebalancer.prd_oldeworld_nb_pxy.id
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancer.prd_oldeworld_nb_pxy.id
  config_id       = data.linode_nodebalancer_config.prd_oldeworld_nb_pxy_config__port_443.id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "prd-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancer.prd_oldeworld_nb_pxy.id
  config_id       = data.linode_nodebalancer_config.prd_oldeworld_nb_pxy_config__port_80.id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "prd-node-pxy-80-${count.index}"
}

resource "akamai_dns_record" "prd_oldeworld_nb_pxy_dnsrecord__public" {
  zone       = local.zone
  recordtype = "A"
  ttl        = 120

  name   = "oldeworld.prd.${var.network_subdomain}.${local.zone}"
  target = [data.linode_nodebalancer.prd_oldeworld_nb_pxy.ipv4]
}
