data "cloudflare_zone" "this" {
  name = var.zone_name
}

# Flexible SSL: CF terminates HTTPS at the edge with Universal SSL;
# CF→origin hop is plain HTTP. Matches the runtime contract documented
# in k3s/gxy-management/apps/artemis/{README.md,values.production.yaml}
# and k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml.
# Any flip to Full / Full (strict) requires origin certs on cassiopeia
# AND artemis simultaneously — multi-PR sequenced change.
resource "cloudflare_zone_settings_override" "this" {
  zone_id = data.cloudflare_zone.this.id

  settings {
    ssl                      = "flexible"
    always_use_https         = "on"
    automatic_https_rewrites = "on"
    min_tls_version          = "1.2"
    tls_1_3                  = "on"
    brotli                   = "on"
    http3                    = "on"
    zero_rtt                 = "on"
    universal_ssl            = "on"
    websockets               = "on"
  }
}
