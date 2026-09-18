datacenter = "dc1"
data_dir   = "/nomad/data"
bind_addr  = "0.0.0.0"

server {
  enabled          = true
  bootstrap_expect = 1
}

vault {
  enabled = true
  address = "http://vault-server:8200"
  token   = "VAULT_TOKEN_PLACEHOLDER"
}

consul {
  address = "consul-dc1-server:8500"
}
