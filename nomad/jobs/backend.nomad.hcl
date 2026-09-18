job "backend" {
  datacenters = ["dc1"]
  type        = "service"

  group "backend" {
    count = 1

    network {
      mode = "bridge"
    }

    task "backend" {
      driver = "docker"

      config {
        image = "hashicorp/http-echo:latest"
        args  = ["-text=Hello from backend", "-listen=:9090"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }

    service {
      name = "backend"
      port = "9090"

      connect {
        sidecar_service {}
      }
    }
  }
}
