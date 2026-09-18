job "nats-publisher" {
  datacenters = ["dc1"]
  type        = "service"

  group "publisher" {
    count = 1

    task "publisher" {
      driver = "docker"

      config {
        image        = "local/nats-demo:1.0"
        network_mode = "hashinet"
        command      = "python"
        args         = ["publisher.py"]
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
