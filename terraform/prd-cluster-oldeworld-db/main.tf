terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freecodecamp"

    workspaces {
      name = "tfws-prd-oldeworld--databases"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

data "linode_instances" "prd_oldeworld_nws" {
  filter {
    name = "tags"
    values = [
      "prd_oldeworld_nws",
      "ops_backoffice"
    ]
  }
}

resource "linode_database_mysql" "prd_oldeworld_nws_db__mysql57" {
  engine_id = "mysql/5.7.39"
  label     = "prd-db-oldeworld-nws-mysql57"
  region    = var.region
  type      = "g6-dedicated-4"

  allow_list = flatten([
    [for i in data.linode_instances.prd_oldeworld_nws.instances : "${i.private_ip_address}/32"]
  ])

  cluster_size     = 3
  replication_type = "asynch"
  ssl_connection   = true

  updates {
    day_of_week   = "sunday"
    duration      = 1
    frequency     = "monthly"
    hour_of_day   = 2
    week_of_month = 2
  }
}

resource "linode_database_mysql" "prd_oldeworld_nws_db__mysql80" {
  engine_id = "mysql/8.0.30"
  label     = "prd-db-oldeworld-nws-mysql80"
  region    = var.region
  type      = "g6-dedicated-4"

  allow_list = flatten([
    [for i in data.linode_instances.prd_oldeworld_nws.instances : "${i.private_ip_address}/32"]
  ])

  cluster_size     = 3
  replication_type = "asynch"
  ssl_connection   = true

  updates {
    day_of_week   = "saturday"  // 2nd Saturday of the month
    duration      = 1
    frequency     = "monthly"
    hour_of_day   = 1           // 2:00am UTC
    week_of_month = 2
  }
}
