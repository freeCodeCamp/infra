# IaC absorb contract for this workspace:
#   1. `imports.sh` must run BEFORE any `terraform apply` (state-pull
#      from the live zone + record set).
#   2. `terraform plan` post-import MUST report zero diff. Non-zero
#      diff means either an attribute we haven't mirrored yet OR live
#      dashboard drift — reconcile by editing the .tf, not the live
#      zone.
#   3. Every resource carries `prevent_destroy = true` (records below
#      get it via the for_each block in records.tf).
data "cloudflare_zone" "this" {
  name = var.zone_name
}

# Flexible SSL: CF terminates HTTPS at the edge with Universal SSL;
# CF→origin hop is plain HTTP. Matches the runtime contract documented
# in k3s/gxy-management/apps/artemis/{README.md,values.production.yaml}
# and k3s/gxy-cassiopeia/apps/caddy/charts/caddy/templates/configmap.yaml.
#
# Trade-off: anyone with the origin droplet IP can bypass the CF WAF
# and hit the origin on plain HTTP. The DO cloud firewall on each
# galaxy narrows inbound 80/443 to the published CF edge CIDRs to keep
# CF as the only path — see `terraform/do-universe-galaxies/firewall.tf`
# `cf_edge_cidrs_v4` / `_v6` variables. Flipping to Full / Full
# (strict) requires origin certs on cassiopeia AND artemis
# simultaneously — multi-PR sequenced change tracked as a follow-up.
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

  lifecycle {
    prevent_destroy = true
  }
}
