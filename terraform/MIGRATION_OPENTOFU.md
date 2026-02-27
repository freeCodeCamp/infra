# OpenTofu + Cloudflare R2 Cutover Instructions

## Goal

- Use OpenTofu for all Terraform stacks in this repo.
- Stop using Terraform Cloud.
- Keep remote state in Cloudflare R2 (encrypted at rest by Cloudflare).
- Perform cutover manually later, stack-by-stack.

## Current Code State

All stacks are already migrated in code from Terraform Cloud backend to:

```hcl
terraform {
  backend "s3" {}
}
```

## Stacks To Migrate

- `ops-standalone`
- `ops-test`
- `ops-stackscripts`
- `stg-cluster-ahoyworld`
- `prd-cluster-ahoyworld`
- `stg-cluster-oldeworld`
- `prd-cluster-oldeworld`
- `stg-cluster-oldeworld-nb`
- `prd-cluster-oldeworld-nb`

## One-Time R2 Setup

1. Create one private R2 bucket for Terraform state.
2. Create an R2 API token with least privilege to this bucket.
3. Keep credentials local (env vars), never in git:

```bash
export AWS_ACCESS_KEY_ID="<R2_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<R2_SECRET_ACCESS_KEY>"
```

4. Use your Cloudflare account ID in endpoint URLs:

```text
https://<ACCOUNT_ID>.r2.cloudflarestorage.com
```

## Backend Config Template (R2)

For each stack, create a local file in `terraform/` (not committed), e.g.
`terraform/<STACK>.backend.hcl`:

```hcl
bucket                      = "<R2_BUCKET_NAME>"
key                         = "<STACK>/terraform.tfstate"
region                      = "auto"
endpoints                   = { s3 = "https://<ACCOUNT_ID>.r2.cloudflarestorage.com" }
use_path_style              = true
skip_region_validation      = true
skip_credentials_validation = true
skip_requesting_account_id  = true
skip_s3_checksum            = true
encrypt                     = true
```

`<STACK>` key values:

- `ops-standalone/terraform.tfstate`
- `ops-test/terraform.tfstate`
- `ops-stackscripts/terraform.tfstate`
- `stg-cluster-ahoyworld/terraform.tfstate`
- `prd-cluster-ahoyworld/terraform.tfstate`
- `stg-cluster-oldeworld/terraform.tfstate`
- `prd-cluster-oldeworld/terraform.tfstate`
- `stg-cluster-oldeworld-nb/terraform.tfstate`
- `prd-cluster-oldeworld-nb/terraform.tfstate`

## Manual Cutover Procedure (Later)

Run this per stack, one at a time, during a maintenance window.

1. Enter stack directory.
2. Ensure no concurrent infra changes are happening.
3. Initialize/migrate backend to R2 using local backend file.
4. Validate state reads correctly.
5. Repeat for next stack.

Suggested command shape:

```bash
cd terraform/<STACK>
tofu init -migrate-state -backend-config=../<STACK>.backend.hcl
```

After all stacks are migrated, use OpenTofu as normal for future `plan/apply` from local operator machines.

## Safety Rules

- Never commit backend config or credential files.
- Only one operator applies at a time per stack.
- Keep bucket private and audit access regularly.

## Unknowns To Watch

1. R2 backend lock behavior under real operator usage.
2. Subtle state drift after migration, even if init succeeds.
3. Provider behavior differences under OpenTofu.
4. Credential scope gaps (backend auth works, provider actions fail).
5. Operator sequencing mistakes (wrong stack/key/file path).
6. Mid-wave migration issues that require rollback.

## Response Playbook

1. Migrate one non-prod stack first and verify before continuing.
2. After each migration, run `tofu state list` in the stack and confirm expected resources exist.
3. Require reviewed `plan` output before first `apply` on migrated stacks.
4. Enforce one-operator-at-a-time execution per stack.
5. Track each stack migration in a log: stack, state key, operator, timestamp, result.
6. Pause the wave immediately on first anomaly and resolve before proceeding.
