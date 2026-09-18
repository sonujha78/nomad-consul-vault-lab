storage "raft" {
  path    = "/vault/data"
  node_id = "vault-dc1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr     = "http://vault-server:8200"
cluster_addr = "http://vault-server:8301"
ui           = true
