# Terraform outputs for the instances module

output "out__sg_id" {
  value       = aws_security_group.mw_sg.id
  description = "Security group for the Staging Mintworld VPC"
}

output "out__subnets" {
  value = {
    private = [for subnet in aws_subnet.mw_subnet_prv : {
      id         = subnet.id
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
    public = [for subnet in aws_subnet.mw_subnet_pub : {
      id         = subnet.id
      name       = subnet.tags["Name"]
      cidr_block = subnet.cidr_block,
    }]
  }
}
