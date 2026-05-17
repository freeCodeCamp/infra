# token reads from DIGITALOCEAN_TOKEN env (galaxy-scoped, per
# $SECRETS_DIR/do-universe/.env.enc). Empty provider block keeps
# `terraform validate` offline-clean.
provider "digitalocean" {
}
