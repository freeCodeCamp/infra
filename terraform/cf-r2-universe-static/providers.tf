# api_token reads from CLOUDFLARE_API_TOKEN env. Provider 5.x asserts
# token format at config-eval time, which breaks `terraform validate`
# in CI unless a real token is wired up — empty block + env-only keeps
# validate offline-clean.
provider "cloudflare" {
}
