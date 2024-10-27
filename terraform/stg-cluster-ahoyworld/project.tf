resource "digitalocean_project" "stg_project" {
  name        = "stg-ahoyworld"
  description = "AhoyWorld staging resources."
  purpose     = "Web Application"
  environment = "Staging"
}

resource "digitalocean_project_resources" "stg_project_resources" {
  project = digitalocean_project.stg_project.id
  resources = flatten([
    [for droplet in digitalocean_droplet.stg_ahoyworld_pxy : droplet.urn],
    [for droplet in digitalocean_droplet.stg_ahoyworld_clt : droplet.urn],
    [for droplet in digitalocean_droplet.stg_ahoyworld_api : droplet.urn]
  ])
}
