# Terraform outputs for the instances module

output "out__mw_sg_id" {
  value       = aws_security_group.mw_sg.id
  description = "Security group for the Staging Mintworld VPC"
}

output "out__mw_sg_web_id" {
  value       = aws_security_group.mw_sg_web.id
  description = "Security group for the Staging Mintworld VPC for Web Proxy"
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

output "out__vpc_id" {
  value       = aws_vpc.mw_vpc.id
  description = "VPC for the Staging Mintworld VPC"
}
