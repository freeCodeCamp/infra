resource "aws_instance" "stg_mw_nomad_wkr" {
  count         = local.count_wkr_nomad
  ami           = data.hcp_packer_artifact.aws_ubuntu.external_identifier
  instance_type = "t3a.medium"
  key_name      = data.aws_key_pair.stg_ssh_service_user_key.key_name

  iam_instance_profile = aws_iam_instance_profile.stg_mw_instance_profile.name

  # Spread the instances across the subnets -- this is a bit of a hack, but it works
  # and an alternative would be to use AWS Auto Scaling Groups.
  subnet_id = aws_subnet.stg_mw_subnet_prv[
    count.index % length(aws_subnet.stg_mw_subnet_prv)
  ].id

  vpc_security_group_ids = [aws_security_group.stg_mw_sg.id]

  private_ip = cidrhost(
    # Pick the cidr_block from the subnet, based on the previous logic.
    aws_subnet.stg_mw_subnet_prv[
      count.index % length(aws_subnet.stg_mw_subnet_prv)
    ].cidr_block,

    # Calculate the host number based on the index and the number of subnets.
    local.hostNum_start_wkr_nomad +
    floor(count.index / length(aws_subnet.stg_mw_subnet_prv))
    + 1
  )

  user_data_base64 = base64encode(templatefile("${path.module}/templates/cloud-init--userdata.yml.tftpl", {
    tf_hostname = "nomad-wkr-${count.index + 1}.mw.stg.${local.zone}"
  }))
  user_data_replace_on_change = true

  tags = merge(
    var.stack_tags,
    {
      Name = "stg-mw-nomad-wkr-${count.index + 1}"
      Role = "nomad_wkr"
    }
  )
}

resource "cloudflare_record" "stg_mw_nomad_wkr_dnsrecord__private" {
  count = length(aws_instance.stg_mw_nomad_wkr)

  zone_id = data.cloudflare_zone.cf_zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "nomad-wkr-${count.index + 1}.mw.stg"
  value = aws_instance.stg_mw_nomad_wkr[count.index].private_ip

  depends_on = [aws_instance.stg_mw_nomad_wkr]
}
