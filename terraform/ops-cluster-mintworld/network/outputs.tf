output "out__vpc" {
  value = aws_vpc.vpc
}

output "out__subnets" {
  value = {
    private = [for subnet in aws_subnet.subnet_prv : {
      id         = subnet.id
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
    public = [for subnet in aws_subnet.subnet_pub : {
      id         = subnet.id
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
  }
}

output "out__sg_main" {
  value = aws_security_group.sg_main
}
