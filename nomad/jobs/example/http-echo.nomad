job "job-http-echo" {

  datacenters = ["*"]
  node_pool   = "stateless"
  type        = "service"

  update {
    max_parallel     = 3
    auto_revert      = true
    health_check     = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "5m"
  }

  migrate {
    max_parallel     = 3
    health_check     = "checks"
    min_healthy_time = "15s"
    healthy_deadline = "5m"
  }

  group "grp-http-echo" {
    count = 10

    network {
      port "http" {
        to = 5678
      }
    }

    service {
      name = "svc-http-echo"
      tags = [
        "app-type=stateless",
        "app-name=http-echo",
        "traefik.enable=true"
      ]
      port     = "http"
      provider = "consul"

      check {
        name                   = "alive"
        type                   = "http"
        path                   = "/"
        interval               = "10s"
        timeout                = "2s"
        success_before_passing = 3
      }

    }

    restart {
      attempts = 2
      interval = "30s"
      delay    = "10s"
      mode     = "fail"
    }


    task "tsk-http-echo" {
      driver = "docker"

      config {
        image = "hashicorp/http-echo"
        args  = ["-text", "Hello! Allocation ID: ${NOMAD_ALLOC_ID} at ${NOMAD_ADDR_http}:${NOMAD_PORT_http}"]
        ports = ["http"]

        # The "auth_soft_fail" configuration instructs Nomad to try public
        # repositories if the task fails to authenticate when pulling images
        # and the Docker driver has an "auth" configuration block.
        auth_soft_fail = true
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}
