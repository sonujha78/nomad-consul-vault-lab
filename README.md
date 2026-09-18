# Nomad + Consul + Vault + Traefik + NATS — Multi-DC Lab

Local Docker-based simulation of a 2-datacenter orchestration stack.
No Kubernetes, no cloud — self-hosted, production-style setup.

## Stack
- **Nomad** — orchestrator (mixed Docker + raw_exec workloads)
- **Consul** — service discovery + service mesh (Consul Connect)
- **Vault** — dynamic PostgreSQL secrets
- **Traefik** — dynamic ingress via Consul catalog
- **NATS** — lightweight pub-sub messaging

## Status
- [x] Consul multi-DC (WAN federated)
- [x] Nomad multi-DC (mixed workloads)
- [ ] Vault dynamic secrets (in progress)
- [ ] Traefik dynamic ingress
- [ ] NATS pub-sub
- [ ] DC1 failure test
