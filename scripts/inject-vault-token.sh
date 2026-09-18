#!/bin/bash
# Injects the real Vault root token into Nomad configs.
# Run this after `vault operator init` and before starting Nomad servers/clients.
set -e

if [ ! -f vault-init.json ]; then
  echo "vault-init.json not found. Run vault operator init first."
  exit 1
fi

ROOT_TOKEN=$(python3 -c "import json; print(json.load(open('vault-init.json'))['root_token'])")

sed -i "s|token   = \"VAULT_TOKEN_PLACEHOLDER\"|token   = \"$ROOT_TOKEN\"|" nomad/dc1-server.hcl
sed -i "s|token   = \"VAULT_TOKEN_PLACEHOLDER\"|token   = \"$ROOT_TOKEN\"|" nomad/dc1-client.hcl

echo "Vault token injected into nomad configs."
