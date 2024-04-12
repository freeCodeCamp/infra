# output "stg_output__consul_svr" {
#   value = {
#     instances = [for instance in aws_instance.stg_mw_consul_svr : {
#       id         = instance.id
#       private_ip = instance.private_ip
#       # public_ip  = instance.public_ip
#       name = instance.tags["Name"]
#     }]
#   }
# }

# output "stg_output__nomad_svr" {
#   value = {
#     instances = [for instance in aws_instance.stg_mw_nomad_svr : {
#       id         = instance.id
#       private_ip = instance.private_ip
#       # public_ip  = instance.public_ip
#       name = instance.tags["Name"]
#     }]
#   }
# }

# output "stg_output__nomad_wkr" {
#   value = {
#     instances = [for instance in aws_instance.stg_mw_nomad_wkr : {
#       id         = instance.id
#       private_ip = instance.private_ip
#       # public_ip  = instance.public_ip
#       name = instance.tags["Name"]
#     }]
#   }
# }
