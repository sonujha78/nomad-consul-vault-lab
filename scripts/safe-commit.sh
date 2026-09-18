#!/bin/bash
# Safely strips the vault token before commit, commits, pushes, then re-injects locally.
set -e
cd "$(dirname "$0")/.."

sed -i 's|token   = "hvs\..*"|token   = "VAULT_TOKEN_PLACEHOLDER"|' nomad/dc1-*.hcl

git add .
git commit -m "$1"
git push

./scripts/inject-vault-token.sh
echo "Done: committed, pushed, and token re-injected locally."
