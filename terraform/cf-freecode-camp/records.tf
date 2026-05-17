locals {
  # Universe-platform DNS records on the freecode.camp zone.
  #
  # `apex_a` + `www_a` + `wildcard_a` all point at the cassiopeia
  # ingress IP — caddy-S3 fronts the `*.freecode.camp` wildcard for
  # every Universe static site and the apex / www landing surface.
  #
  # `uploads_a` points at the gxy-management ingress — artemis deploy
  # proxy is the only authenticated write surface on the zone
  # (ADR-016).
  #
  # All records are CF-proxied (orange-cloud) so Flexible SSL applies
  # and rate-limit / WAF rules attach. TTL is ignored when proxied —
  # CF holds it at 1 (auto).
  records = {
    apex_a = {
      name    = "@"
      type    = "A"
      content = var.cassiopeia_ingress_ipv4
      proxied = true
      ttl     = 1
      comment = "apex; cassiopeia caddy-S3 wildcard root"
    }
    www_a = {
      name    = "www"
      type    = "A"
      content = var.cassiopeia_ingress_ipv4
      proxied = true
      ttl     = 1
      comment = "www; cassiopeia caddy-S3 wildcard root"
    }
    wildcard_a = {
      name    = "*"
      type    = "A"
      content = var.cassiopeia_ingress_ipv4
      proxied = true
      ttl     = 1
      comment = "wildcard *.freecode.camp; cassiopeia caddy-S3 reads <slug>.freecode.camp/<deploy>/ from R2"
    }
    uploads_a = {
      name    = "uploads"
      type    = "A"
      content = var.management_ingress_ipv4
      proxied = true
      ttl     = 1
      comment = "artemis deploy proxy (gxy-management); auth surface for universe-cli"
    }
  }
}

resource "cloudflare_record" "this" {
  for_each = local.records

  zone_id = data.cloudflare_zone.this.id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  proxied = each.value.proxied
  ttl     = each.value.ttl
  comment = each.value.comment
}
