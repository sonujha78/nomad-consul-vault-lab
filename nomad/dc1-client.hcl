datacenter = "dc1"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

client {
  enabled = true
  servers = ["nomad-dc1-server:4647"]
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}

consul {
  address = "consul-dc1-server:8500"
}
