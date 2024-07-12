job "http-echo" {

  datacenters = ["*"]
  type        = "service"

  constraint {
    attribute = "${meta.role}"
    value     = "worker-stateless"
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
        name     = "alive"
        type     = "tcp"
        interval = "10s"
        timeout  = "2s"
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
