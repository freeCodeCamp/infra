data linode_nodebalancers stg_oldeworld_pxy_nbs {
  filter {
    name = "label"
    values = ["stg-nb-oldeworld-pxy"]
  }
}

data linode_nodebalancer_configs stg_oldeworld_pxy_nb_configs__port_443 {
  nodebalancer_id = data.linode_nodebalancers.stg_oldeworld_pxy_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["443"]
  }
}

data linode_nodebalancer_configs stg_oldeworld_pxy_nb_configs__port_80 {
  nodebalancer_id = data.linode_nodebalancers.stg_oldeworld_pxy_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["80"]
  }
}
resource "linode_nodebalancer_node" "stg_oldeworld_nb_pxy_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.stg_oldeworld_pxy_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.stg_oldeworld_pxy_nb_configs__port_443.nodebalancer_configs[0].id
  address         = "${linode_instance.stg_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "stg-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "stg_oldeworld_nb_pxy_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.stg_oldeworld_pxy_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.stg_oldeworld_pxy_nb_configs__port_80.nodebalancer_configs[0].id
  address         = "${linode_instance.stg_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "stg-node-pxy-80-${count.index}"
}

resource "cloudflare_record" "stg_oldeworld_nb_pxy_dnsrecord__public" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "oldeworld.stg.${var.network_subdomain}"
  value = data.linode_nodebalancers.stg_oldeworld_pxy_nbs.nodebalancers[0].ipv4
}
