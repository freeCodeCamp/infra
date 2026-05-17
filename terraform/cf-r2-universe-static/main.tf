# Single R2 bucket fronting every Universe static deploy. Object
# layout (per ADR-016 + artemis/values.production.yaml):
#
#   <site>.freecode.camp/production         → alias pointer (small)
#   <site>.freecode.camp/preview            → alias pointer (small)
#   <site>.freecode.camp/deploys/<id>/...   → immutable deploy bytes
#
# Aliases are overwritten by artemis on every promote/rollback;
# deploys/ prefixes accumulate and are aged out by the artemis-side
# archive sweep cron (see prior dossier
# 2026-05-11-archive-sweep-ga-hardening). Bucket-level versioning is
# NOT used — the deploy-id prefix scheme provides immutability +
# rollback semantics already.
#
# IaC absorb contract for this workspace:
#   1. `imports.sh` must run BEFORE any `terraform apply` (state-pull
#      from the live bucket).
#   2. `terraform plan` post-import MUST report zero diff. Non-zero
#      diff means either drift in `var.*` defaults or an attribute the
#      provider surfaces that isn't yet mirrored in this file — fix
#      the .tf, not the live bucket.
#   3. Every resource carries `prevent_destroy = true`. Operator who
#      genuinely needs to destroy must edit the .tf to remove the
#      lifecycle guard FIRST, then plan + apply.
resource "cloudflare_r2_bucket" "this" {
  account_id = var.cloudflare_account_id
  name       = var.bucket_name
  location   = var.bucket_location

  lifecycle {
    prevent_destroy = true
  }
}

# Lifecycle rule: abort-incomplete-uploads only.
#
# The prior `sweep-stale-deploys` rule used `prefix = ""` which the R2
# API matches as "every object in the bucket" — including the alias
# pointers at `<site>.freecode.camp/production` + `/preview`. After
# the age window passed, any site that wasn't touched would lose its
# production pointer and stop serving. R2 lifecycle prefix-match is
# literal-prefix, NOT path-glob, so no single prefix can target
# `<site>.freecode.camp/deploys/<id>/` without also matching alias
# pointers under the same `<site>.freecode.camp/` parent. Removing the
# rule entirely is the safe move; the artemis archive-sweep cron
# already owns this responsibility and operates with site-scoped
# awareness.
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
  ]

  lifecycle {
    prevent_destroy = true
  }
}
