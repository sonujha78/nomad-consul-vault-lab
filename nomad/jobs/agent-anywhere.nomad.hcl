job "agent-anywhere" {
  datacenters = ["dc1", "dc2"]
  type        = "service"

  group "agent" {
    count = 1

    task "heartbeat" {
      driver = "raw_exec"

      config {
        command = "/bin/sh"
        args    = ["-c", "while true; do echo \"[agent-anywhere] alive on $(hostname) at $(date)\"; sleep 5; done"]
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
