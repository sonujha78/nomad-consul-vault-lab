job "nats-subscriber" {
  datacenters = ["dc1"]
  type        = "service"

  group "subscriber" {
    count = 1

    task "subscriber" {
      driver = "docker"

      config {
        image        = "local/nats-demo:1.0"
        network_mode = "hashinet"
        command      = "python"
        args         = ["subscriber.py"]
      }

      resources {
        cpu    = 50
        memory = 64
      }
    }
  }
}
