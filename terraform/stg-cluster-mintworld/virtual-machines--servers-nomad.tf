
resource "aws_instance" "stg_mintworld_nomad_svr" {
  count         = local.nomad_svr_count
  ami           = data.hcp_packer_artifact.aws_ubuntu.external_identifier
  instance_type = "t3a.medium"
  key_name      = data.aws_key_pair.stg_ssh_service_user_key.key_name

  associate_public_ip_address = true
  subnet_id                   = aws_subnet.stg_mintworld_subnet[count.index % length(aws_subnet.stg_mintworld_subnet)].id
  private_ip = cidrhost(
    "${element(local.subnet_base_ips, count.index % length(local.subnet_base_ips))}/18",
    local.ip_start_block_nomad_svr + floor(count.index / length(local.subnet_base_ips)) + 1
  )

  tags = merge(
    var.stack_tags,
    {
      Name               = "stg-mintworld-nomad-svr-${count.index + 1}"
      Role               = "nomad_svr"
      Nomad_AutoJoin_Tag = "stg-mintworld-nomad-svr"
    }
  )

  user_data_base64 = base64encode(templatefile("${path.module}/templates/cloud-init--userdata.yml.tftpl", {
    tf_hostname           = "nomad-svr-${count.index + 1}.mintworld.stg.${local.zone}",
    tf_tailscale_auth_key = var.tailscale_auth_key,
    tf_tailscale_hostname = "stg-vm-mintworld-nomad-svr-${count.index + 1}"
  }))
  user_data_replace_on_change = var.user_data_replace_on_change
}

resource "cloudflare_record" "stg_mintworld_nomad_svr_dnsrecord__public" {
  count = length(aws_instance.stg_mintworld_nomad_svr)

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "pub.nomad-svr-${count.index + 1}.mintworld.stg.${var.network_subdomain}"
  value = aws_instance.stg_mintworld_nomad_svr[count.index].public_ip

  depends_on = [aws_instance.stg_mintworld_nomad_svr]
}

resource "cloudflare_record" "stg_mintworld_nomad_svr_dnsrecord__private" {
  count = length(aws_instance.stg_mintworld_nomad_svr)

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "nomad-svr-${count.index + 1}.mintworld.stg"
  value = aws_instance.stg_mintworld_nomad_svr[count.index].private_ip

  depends_on = [aws_instance.stg_mintworld_nomad_svr]
}
