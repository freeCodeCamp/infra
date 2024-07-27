job "job-traefik" {

  datacenters = ["*"]
  type        = "system"

  constraint {
    attribute = "${node.class}"
    value     = "web"
  }

  update {
    max_parallel     = 1
    auto_revert      = true
    health_check     = "checks"
    min_healthy_time = "15s"
    stagger          = "30s"
    healthy_deadline = "5m"
  }

  group "grp-traefik" {

    network {
      port "http" {
        static = 80
      }

      port "traefik" {
        static = 8081
      }

      port "ping" {
        static = 8082
      }
    }

    service {
      name = "svc-traefik"

      check {
        name     = "alive"
        type     = "http"
        port     = "ping"
        path     = "/ping"
        interval = "5s"
        timeout  = "2s"
      }
    }

    task "tsk-traefik" {
      driver = "docker"

      config {
        image        = "traefik:v3.1"
        network_mode = "host"

        volumes = [
          "local/traefik.yaml:/etc/traefik/traefik.yaml",
        ]
      }

      template {
        // Intentional use of left_delimiter and right_delimiter to avoid interpolation
        left_delimiter  = "[["
        right_delimiter = "]]"
        // Intentional use of left_delimiter and right_delimiter to avoid interpolation
        data        = file(fileexists("config.yaml") ? "config.yaml" : abspath("jobs/web/config.yaml"))
        destination = "local/traefik.yaml"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
