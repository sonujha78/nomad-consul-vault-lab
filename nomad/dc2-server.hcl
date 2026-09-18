datacenter = "dc2"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1
}

consul {
  address = "consul-dc2-server:8500"
}
