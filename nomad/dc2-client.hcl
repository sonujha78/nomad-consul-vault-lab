datacenter = "dc2"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

client {
  enabled = true
  servers = ["nomad-dc2-server:4647"]
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

consul {
  address = "consul-dc2-server:8500"
}
