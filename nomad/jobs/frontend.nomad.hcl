job "frontend" {
  datacenters = ["dc1"]
  type        = "service"

  group "frontend" {
    count = 1

    network {
      mode = "bridge"
      port "http" {
        static = 8080
        to     = 8080
      }
    }

    task "frontend" {
      driver = "docker"

      config {
        image   = "curlimages/curl:latest"
        command = "/bin/sh"
        args    = ["-c", "while true; do curl -s http://localhost:9091 || echo 'waiting for backend via sidecar'; sleep 5; done"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "frontend"
      port = "http"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "backend"
              local_bind_port  = 9091
            }
          }
        }
      }
    }
  }
}
