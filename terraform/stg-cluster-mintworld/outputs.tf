output "stg_output__consul_svr" {
  value = {
    instances = [for instance in aws_instance.stg_mw_consul_svr : {
      id         = instance.id
      private_ip = instance.private_ip
      # public_ip  = instance.public_ip
      name = instance.tags["Name"]
    }]
  }
}

output "stg_output__nomad_svr" {
  value = {
    instances = [for instance in aws_instance.stg_mw_nomad_svr : {
      id         = instance.id
      private_ip = instance.private_ip
      # public_ip  = instance.public_ip
      name = instance.tags["Name"]
    }]
  }
}

output "stg_output__nomad_wkr" {
  value = {
    instances = [for instance in aws_instance.stg_mw_nomad_wkr : {
      id         = instance.id
      private_ip = instance.private_ip
      # public_ip  = instance.public_ip
      name = instance.tags["Name"]
    }]
  }
}

output "stg_output__subnet_cidr_blocks" {
  value = {
    private = [for subnet in aws_subnet.stg_mw_subnet_prv : {
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
    public = [for subnet in aws_subnet.stg_mw_subnet_pub : {
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
  }
}
