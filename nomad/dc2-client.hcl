datacenter = "dc2"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

client {
  enabled  = true
  servers  = ["nomad-dc2-server:4647"]
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

consul {
  address = "consul-dc2-server:8500"
}
