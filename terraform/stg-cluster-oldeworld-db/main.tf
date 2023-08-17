terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-stg-oldeworld--databases"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

data "linode_instances" "stg_oldeworld_nws" {
  filter {
    name = "group"
    values = [
      "stg_oldeworld_nws",
    ]
  }
}

resource "linode_database_mysql" "stg_oldeworld_nws_db__mysql57" {
  engine_id = "mysql/5.7.39"
  label     = "stg-db-oldeworld-nws-mysql57"
  region    = var.region
  type      = "g6-standard-2"

  allow_list = flatten([
    [for i in data.linode_instances.stg_oldeworld_nws.instances : "${i.private_ip_address}/32"]
  ])

  cluster_size     = 3
  replication_type = "asynch"
  ssl_connection   = true

  # Do maintenance on every 2nd Saturday at 2am UTC, maximum maintenance window of 1 hour.
  updates {
    day_of_week   = "saturday"
    duration      = 1
    frequency     = "monthly"
    hour_of_day   = 2
    week_of_month = 2
  }
}
