# Single R2 bucket fronting every Universe static deploy. Object
# layout (per ADR-016 + artemis/values.production.yaml):
#
#   <site>.freecode.camp/production         → alias pointer (small)
#   <site>.freecode.camp/preview            → alias pointer (small)
#   <site>.freecode.camp/deploys/<id>/...   → immutable deploy bytes
#
# Aliases are overwritten by artemis on every promote/rollback;
# deploys/ prefixes accumulate and rely on the archive sweep cron to
# age out. Bucket-level versioning is NOT used — the deploy-id prefix
# scheme provides immutability + rollback semantics already.
resource "cloudflare_r2_bucket" "this" {
  account_id = var.cloudflare_account_id
  name       = var.bucket_name
  location   = var.bucket_location
}

# Lifecycle rules cover two concerns:
#
#   1. abort-incomplete-uploads — caps the orphaned multipart-upload
#      buffer that builds up when universe-cli crashes mid-deploy
#      (operator never finalizes; R2 holds the parts indefinitely).
#
#   2. deploy-prefix-sweep — ages out `*/deploys/<id>/` objects beyond
#      var.deploy_retention_days. Production / preview alias pointers
#      live OUTSIDE that prefix and are NOT eligible for deletion, so
#      they're never swept.
resource "cloudflare_r2_bucket_lifecycle" "this" {
  account_id  = var.cloudflare_account_id
  bucket_name = cloudflare_r2_bucket.this.name

  rules = [
    {
      id      = "abort-incomplete-uploads"
      enabled = true
      conditions = {
        prefix = ""
      }
      abort_multipart_uploads_transition = {
        condition = {
          max_age = var.abort_incomplete_uploads_days * 24 * 60 * 60
          type    = "Age"
        }
      }
    },
    {
      id      = "sweep-stale-deploys"
      enabled = true
      conditions = {
        # All Universe deploy-id prefixes match the pattern
        # `<site>.freecode.camp/deploys/`. R2 lifecycle prefix match
        # is substring, so trailing `/deploys/` would also match
        # `<site>/deploys/...` if site naming ever drops the
        # `.freecode.camp` suffix. Current artemis pin is FQDN-only.
        prefix = ""
      }
      delete_objects_transition = {
        condition = {
          max_age = var.deploy_retention_days * 24 * 60 * 60
          type    = "Age"
        }
      }
    },
  ]
}
