datacenter = "dc1"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

client {
  enabled  = true
  servers  = ["nomad-dc1-server:4647"]
  cni_path = "/opt/cni/bin"
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

plugin "docker" {
  config {
    extra_labels = ["job_name", "task_group_name", "task_name"]
    gc {
      image = true
    }
  }
}

vault {
  enabled = true
  address = "http://vault-server:8200"
  token   = "VAULT_TOKEN_PLACEHOLDER"
}

consul {
  address = "consul-dc1-server:8500"
}
