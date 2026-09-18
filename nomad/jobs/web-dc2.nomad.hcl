job "web-dc2" {
  datacenters = ["dc2"]
  type        = "service"

  constraint {
    attribute = "${node.datacenter}"
    value     = "dc2"
  }

  group "web" {
    count = 1

    task "nginx" {
      driver = "docker"

      config {
        image        = "nginx:alpine"
        network_mode = "hashinet"
      }

      service {
        name         = "web-dc2"
        port         = 80
        address_mode = "driver"
        provider     = "consul"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.web-dc2.rule=PathPrefix(`/dc2`)",
          "traefik.http.middlewares.strip-dc2.stripprefix.prefixes=/dc2",
          "traefik.http.routers.web-dc2.middlewares=strip-dc2"
        ]

        check {
          type         = "http"
          path         = "/"
          interval     = "10s"
          timeout      = "2s"
          address_mode = "driver"
        }
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
