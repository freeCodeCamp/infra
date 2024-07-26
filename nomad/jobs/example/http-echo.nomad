job "job-http-echo" {

  datacenters = ["*"]
  type        = "service"

  constraint {
    attribute = "${node.class}"
    value     = "stateless"
  }

  update {
    max_parallel     = 3
    canary           = 1
    auto_revert      = true
    auto_promote     = true
    health_check     = "task_states"
    min_healthy_time = "10s"
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
        "global",
        "http-echo",
        "traefik.enable=true",
        "traefik.http.routers.http.rule=Path(`/http-echo`)"
      ]
      port     = "http"
      provider = "consul"

      check {
        name                   = "alive"
        type                   = "http"
        path                   = "/"
        interval               = "3s"
        timeout                = "5s"
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
