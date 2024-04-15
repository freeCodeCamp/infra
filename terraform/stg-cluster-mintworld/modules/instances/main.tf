resource "aws_instance" "mw_instance" {
  count         = var.instance_count
  ami           = var.ami
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile = var.iam_instance_profile

  # Spread the instances across the subnets -- this is a bit of a hack, but it works
  # and an alternative would be to use AWS Auto Scaling Groups.
  subnet_id = var.subnets[count.index % length(var.subnets)].id

  vpc_security_group_ids = var.security_group_ids

  private_ip = cidrhost(
    # Pick the cidr_block from the subnet, based on the previous logic.
    var.subnets[count.index % length(var.subnets)].cidr_block,
    # Calculate the host number based on the index and the number of subnets.
    var.hostNum_start + floor(count.index / length(var.subnets)) + 1
  )

  user_data_base64 = base64encode(templatefile("${path.module}/templates/cloud-init--userdata.yml.tftpl", {
    tf_hostname = "${var.instance_prefix}-${count.index + 1}.mw.${var.instance_env}.${var.zone.name}"
  }))
  user_data_replace_on_change = var.user_data_replace_on_change

  tags = merge(
    var.stack_tags,
    {
      Name = "${var.instance_env}-mw-${var.instance_prefix}-${count.index + 1}"
      Role = var.instance_prefix
    }
  )
}

resource "cloudflare_record" "mw_instance_dnsrecord__private" {
  count = var.create_dns_records__private ? length(aws_instance.mw_instance) : 0

  zone_id = var.zone.id
  type    = "A"
  proxied = false
  ttl     = 120

  name  = "${var.instance_prefix}-${count.index + 1}.mw.${var.instance_env}"
  value = aws_instance.mw_instance[count.index].private_ip

  depends_on = [aws_instance.mw_instance]
}
