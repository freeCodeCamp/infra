terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-ops-stackscripts"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

# Based on https://github.com/displague/terraform-linode-cloudinit-example
resource "linode_stackscript" "cloudinit_stackscript" {
  script = chomp(file("${path.module}/stackscript.sh"))

  description = <<EOF
This StackScript takes a base64 encoded `userdata` variable which will be provided to `cloud-init` on boot.

See README.md for more information.
EOF

  rev_note = "Initial version"
  images   = ["any/all"]

  is_public = var.public_stackscript
  label     = "CloudInit"
}
