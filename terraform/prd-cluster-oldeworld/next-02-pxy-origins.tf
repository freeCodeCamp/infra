data linode_nodebalancers prd_oldeworld_pxy_1_nbs {
  filter {
    name = "label"
    values = ["prd-nb-oldeworld-pxy-1"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_1_nb_configs__port_443 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_1_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["443"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_1_nb_configs__port_80 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_1_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["80"]
  }
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_1_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_1_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_1_nb_configs__port_443.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "prd-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_1_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_1_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_1_nb_configs__port_80.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "prd-node-pxy-80-${count.index}"
}

data linode_nodebalancers prd_oldeworld_pxy_2_nbs {
  filter {
    name = "label"
    values = ["prd-nb-oldeworld-pxy-2"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_2_nb_configs__port_443 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_2_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["443"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_2_nb_configs__port_80 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_2_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["80"]
  }
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_2_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_2_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_2_nb_configs__port_443.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "prd-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_2_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_2_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_2_nb_configs__port_80.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "prd-node-pxy-80-${count.index}"
}

data linode_nodebalancers prd_oldeworld_pxy_3_nbs {
  filter {
    name = "label"
    values = ["prd-nb-oldeworld-pxy-3"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_3_nb_configs__port_443 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_3_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["443"]
  }
}

data linode_nodebalancer_configs prd_oldeworld_pxy_3_nb_configs__port_80 {
  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_3_nbs.nodebalancers[0].id
  filter {
    name = "port"
    values = ["80"]
  }
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_3_nodes__port_443" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_3_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_3_nb_configs__port_443.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:443"
  label           = "prd-node-pxy-443-${count.index}"
}

resource "linode_nodebalancer_node" "prd_oldeworld_nb_pxy_3_nodes__port_80" {
  count = local.pxy_node_count

  nodebalancer_id = data.linode_nodebalancers.prd_oldeworld_pxy_3_nbs.nodebalancers[0].id
  config_id       = data.linode_nodebalancer_configs.prd_oldeworld_pxy_3_nb_configs__port_80.nodebalancer_configs[0].id
  address         = "${linode_instance.prd_oldeworld_pxy[count.index].private_ip_address}:80"
  label           = "prd-node-pxy-80-${count.index}"
}

resource "cloudflare_record" "prd_oldeworld_nb_pxy_dnsrecord__public" {
  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "oldeworld.prd.${var.network_subdomain}"
  value = data.linode_nodebalancers.prd_oldeworld_pxy_1_nbs.nodebalancers[0].ipv4
}
