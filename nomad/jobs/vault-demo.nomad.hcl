job "vault-demo" {
  datacenters = ["dc1"]
  type        = "service"

  group "app" {
    count = 1

    task "app" {
      driver = "raw_exec"

      vault {
        policies = ["app-policy"]
      }

      config {
        command = "/bin/sh"
        args    = ["-c", "while true; do echo \"--- $(date) ---\"; echo \"DB creds from Vault:\"; cat secrets/db-creds.env; sleep 15; done"]
      }

      template {
        data = <<EOT
{{ with secret "database/creds/app-role" }}
DB_USERNAME={{ .Data.username }}
DB_PASSWORD={{ .Data.password }}
LEASE_DURATION={{ .LeaseDuration }}
{{ end }}
EOT
        destination = "secrets/db-creds.env"
        change_mode = "noop"
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
