job "web-dc1" {
  datacenters = ["dc1"]
  type        = "service"

  constraint {
    attribute = "${node.datacenter}"
    value     = "dc1"
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
        name         = "web-dc1"
        port         = 80
        address_mode = "driver"
        provider     = "consul"

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
