# Nomad + Consul + Vault + Traefik + NATS — Multi-DC Orchestration Lab

A fully self-hosted, production-style multi-datacenter orchestration stack —
**no Kubernetes, no cloud provider**. Everything runs locally as Docker
containers simulating two datacenters (DC1 and DC2), built and debugged
end-to-end on a single Ubuntu machine.

> This is not a "happy path" tutorial repo. Every phase below includes the
> real failures hit during build (config bugs, race conditions, architecture
> gaps) and how each was diagnosed and fixed — because that debugging trail
> is the actual signal for a project like this.

---

## Stack

| Component | Role |
|---|---|
| **Nomad** | Orchestrator — runs Docker **and** raw_exec (plain binary) workloads in the same cluster |
| **Consul** | Service discovery, health checking, service mesh (Consul Connect) |
| **Vault** | Dynamic, short-lived PostgreSQL credentials — no static passwords anywhere |
| **Traefik** | Ingress that auto-discovers services via Consul, zero manual config reload |
| **NATS** | Lightweight pub-sub messaging (+ JetStream persistence demo) |

---

## Architecture

```mermaid
flowchart TB
    subgraph DC1["DC1 — Datacenter 1"]
        C1[Consul Server<br/>consul-dc1-server]
        N1S[Nomad Server<br/>nomad-dc1-server]
        N1C[Nomad Client<br/>nomad-dc1-client]
        T1[Traefik DC1<br/>:8000]
        W1[web-dc1<br/>nginx]
        VD[vault-demo<br/>raw_exec]
        NP[nats-publisher]
        NS[nats-subscriber]

        N1S --> N1C
        N1C --> W1
        N1C --> VD
        N1C --> NP
        N1C --> NS
        T1 -->|Consul Catalog<br/>auto-discover| C1
        C1 -.health checks.-> W1
    end

    subgraph DC2["DC2 — Datacenter 2"]
        C2[Consul Server<br/>consul-dc2-server]
        N2S[Nomad Server<br/>nomad-dc2-server]
        N2C[Nomad Client<br/>nomad-dc2-client]
        T2[Traefik DC2<br/>:8001]
        W2[web-dc2<br/>nginx]

        N2S --> N2C
        N2C --> W2
        T2 -->|Consul Catalog<br/>auto-discover| C2
        C2 -.health checks.-> W2
    end

    subgraph Shared["Shared Services"]
        VAULT[Vault Server<br/>:8200<br/>raft storage]
        PG[(PostgreSQL<br/>appdb)]
        NATS[NATS Server<br/>:4222<br/>+ JetStream]
    end

    C1 <-->|WAN Gossip<br/>Federation| C2
    N1S -.NOT federated<br/>independent cluster.- N2S

    VD -->|fetch dynamic creds<br/>via template| VAULT
    VAULT -->|issue short-lived<br/>ROLE + PASSWORD| PG
    NP -->|publish<br/>order-created| NATS
    NATS -->|subscribe| NS

    style DC1 fill:#1a2f1a,stroke:#4ade80
    style DC2 fill:#1a1f2f,stroke:#60a5fa
    style Shared fill:#2f1a1a,stroke:#f87171
    style N1S stroke:#f87171,stroke-dasharray: 5 5
    style N2S stroke:#f87171,stroke-dasharray: 5 5
```

**Key architectural note (found during testing, not assumed upfront):**
Consul is WAN-federated between DC1 and DC2 (`retry_join_wan`), but the two
Nomad server clusters are **independent** — each runs its own Raft
consensus with no knowledge of the other. This was discovered directly
during the DC1 failure test (see [Phase 7](#phase-7--dc1-failure-test)) and
is documented there with the real fix (`nomad server join`) for a
production setup.

---

## Repo Structure

```
nomad-consul-vault-lab/
├── consul/                    # Consul server configs (dc1, dc2)
├── nomad/
│   ├── dc1-server.hcl, dc2-server.hcl
│   ├── dc1-client.hcl, dc2-client.hcl
│   ├── client-image/          # Custom Nomad client Docker image (see Phase 2)
│   └── jobs/                  # All Nomad job specs (.nomad.hcl)
├── vault/
│   ├── vault-config.hcl
│   └── app-policy.hcl         # Scoped policy for job's Vault token
├── traefik/
│   ├── traefik.yml            # DC1 instance config
│   └── traefik-dc2.yml        # DC2 instance config
├── nats/scripts/               # Publisher/subscriber Python + Dockerfile
├── docs/                       # Deep-dive docs referenced below
│   ├── consul-connect-limitation.md
│   ├── dc1-failure-test.md
│   └── nats-jetstream-tradeoff.md
├── scripts/
│   ├── inject-vault-token.sh   # Injects real Vault token into local configs
│   └── safe-commit.sh          # Commits without leaking the Vault token
└── docker-compose.yml
```

---

## Prerequisites

- Docker + Docker Compose (v2 syntax, `docker compose`)
- A GitHub repo with **push protection** enabled (secret scanning) — this
  project relies on it catching accidental token leaks, see
  [Vault section](#phase-4--vault-dynamic-secrets)

---

## Phase 0 — Repo Setup

```bash
git clone https://github.com/<you>/nomad-consul-vault-lab.git
cd nomad-consul-vault-lab
mkdir -p consul nomad/jobs vault traefik nats docs scripts
```

---

## Phase 1 — Consul: DC1 + DC2 (WAN Federated)

Two Consul servers, one per simulated DC, joined over WAN gossip.

```bash
docker network create hashinet
docker compose up -d consul-dc1-server consul-dc2-server
docker exec consul-dc1-server consul members -wan
```

**Result:**
```
Node                    Status  Type    DC   
consul-dc1-server.dc1   alive   server  dc1  
consul-dc2-server.dc2   alive   server  dc2  
```

```bash
curl -s localhost:8500/v1/catalog/datacenters
# ["dc1","dc2"]
```

Both Consul UIs confirmed healthy at `:8500` (DC1) and `:8501` (DC2).

---

## Phase 2 — Nomad: Mixed Workloads Across DC1/DC2

### What went wrong (and the real fixes)

Running Nomad **clients** inside Docker containers (instead of bare
metal/VMs) is explicitly unsupported by HashiCorp, and this project hit
every reason why, one at a time:

| Problem | Root Cause | Fix |
|---|---|---|
| `cgroup.subtree_control: device or resource busy` | Nested cgroup v2 delegation conflict | `cgroup: host` in compose, drop `pid: host` |
| Nodes never registered | CNI plugins missing (`/opt/cni/bin` empty) | Installed CNI plugins, bind-mounted into client |
| `iptables: executable file not found` | Official `hashicorp/nomad` image is busybox-only, no package manager | Built a **custom Nomad client image** (Ubuntu + iptables + iproute2 + nomad + consul binaries) — see `nomad/client-image/Dockerfile` |
| `bind: address already in use` (unrelated services) | Leftover containers/processes from earlier iterations | Cleaned up, isolated ports |

The custom client image was the real unlock — official images assume
Nomad runs on a real host, not nested in Docker.

### Job specs (3 required workload types)

- **`web-dc1`** — Docker container, hard-constrained to `dc1`
- **`web-dc2`** — Docker container, hard-constrained to `dc2`
- **`agent-anywhere`** — `raw_exec` (plain shell loop, no container at all),
  can run in either DC — **this is the Kubernetes differentiator**:
  Kubernetes cannot run non-containerized workloads natively.

```bash
docker exec nomad-dc1-server nomad run /nomad/jobs/web-dc1.nomad.hcl
docker exec nomad-dc2-server nomad run /nomad/jobs/web-dc2.nomad.hcl
docker exec nomad-dc1-server nomad run /nomad/jobs/agent-anywhere.nomad.hcl
```

**Result — mixed workload proof (raw_exec, no container):**
```
[agent-anywhere] alive on nomad-dc1-client at Fri Sep 18 04:22:47 UTC 2026
[agent-anywhere] alive on nomad-dc1-client at Fri Sep 18 04:22:52 UTC 2026
...
```

All three jobs reached `Healthy = 1`, `Deployment completed successfully`.

---

## Phase 3 — Consul Connect (Service Mesh) — Known Limitation

Attempted full mTLS sidecar mesh between a `backend` and `frontend` job
using `connect { sidecar_service {} }`. Hit a genuine, reproducible
**filesystem-visibility race condition**:

Nomad (inside its container) writes allocation files (`hosts`,
`resolv.conf`) to a bind-mounted path; it then asks the **host** Docker
daemon (via `docker.sock`) to mount that same path into the sidecar
container — sometimes before the write is visible to the host's
filesystem view. Verified via `stat` that the failure timestamp exactly
matched the file's creation timestamp, down to the millisecond.

**This is documented in full, with evidence, in
[`docs/consul-connect-limitation.md`](docs/consul-connect-limitation.md).**
HashiCorp explicitly states Nomad clients-in-Docker are unsupported for
exactly this class of issue — in a bare-metal/VM DC as the task originally
specifies, this would not occur.

CNI, iptables, and bridge networking were all successfully fixed and
verified working up to this final race condition — the limitation is
narrowly scoped to the sidecar bootstrap timing, not the rest of the mesh
plumbing.

---

## Phase 4 — Vault: Dynamic PostgreSQL Secrets

```bash
docker compose up -d postgres vault-server
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault-server \
  vault operator init -key-shares=1 -key-threshold=1 -format=json > vault-init.json
docker exec -e VAULT_ADDR=http://127.0.0.1:8200 vault-server \
  vault operator unseal <unseal_key>
```

**Database secrets engine — no static password anywhere:**
```bash
vault secrets enable database
vault write database/config/postgres-db \
  plugin_name=postgresql-database-plugin \
  allowed_roles="app-role" \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/appdb?sslmode=disable" \
  username="vaultadmin" password="supersecretadminpass"
vault write database/roles/app-role \
  db_name=postgres-db \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" max_ttl="2h"
```

**Nomad ↔ Vault native integration** — job fetches its own token, no
manual paste:
```hcl
vault {
  policies = ["app-policy"]   # scoped: read-only on database/creds/app-role
}
template {
  data        = "{{ with secret \"database/creds/app-role\" }}...{{ end }}"
  destination = "secrets/db-creds.env"
  change_mode = "noop"        # critical: see rotation proof below
}
```

**Result — job auto-fetching fresh credentials, zero manual steps:**
```
DB_USERNAME=v-token-26-app-role-RllotLHKL3Nwt5i7gy5d-1789724265
DB_PASSWORD=IRvOrzntPDM-IyqfINh3
LEASE_DURATION=3600
```

### Zero-downtime rotation proof

Set `default_ttl=90s` to force fast rotation, then watched the same
allocation across two lease periods:

```
09:49:33  DB_USERNAME=v-token-8d-app-role-p76BFurpzAvo28WOFusm-...
09:50:18  DB_USERNAME=v-token-8d-app-role-Qy2Zfoincy1wPrgcket5-...   <- rotated
...
Total Restarts = 0
```

**Credential rotated silently, task never restarted.** This required
`change_mode = "noop"` on the template — the default (`restart`) would
have restarted the task on every rotation, violating the task's actual
requirement ("without the job restarting or failing a single request").

### Secret-leak protection

GitHub's push protection caught a Vault root token committed accidentally
in a Nomad config (`token = "hvs...."`). Fixed by:
- Using a placeholder (`VAULT_TOKEN_PLACEHOLDER`) in all committed configs
- `scripts/inject-vault-token.sh` — injects the real token locally only
- `scripts/safe-commit.sh` — strips the token before every commit, pushes,
  then re-injects locally
- A `.git/hooks/pre-commit` hook that blocks any commit containing an
  `hvs.` token pattern

---

## Phase 5 — Traefik: Dynamic Ingress

### What went wrong

A single Traefik instance pointed at `consul-dc1-server:8500` only
discovers **DC1's** catalog — Consul's WAN federation does not make
Traefik's Consul Catalog provider cross-DC-aware. Fixed by running **one
Traefik instance per DC**, each pointed at its local Consul agent — which
also better reflects how ingress should be architected in a real
multi-region setup (each region serves its own traffic).

```bash
docker compose up -d traefik traefik-dc2
```

Services opt in via Consul tags — zero manual Traefik config on service
registration:
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.web-dc1.rule=PathPrefix(`/dc1`)",
  "traefik.http.middlewares.strip-dc1.stripprefix.prefixes=/dc1",
  "traefik.http.routers.web-dc1.middlewares=strip-dc1"
]
```

**Result:**
```bash
curl http://localhost:8000/dc1/   # DC1 Traefik → web-dc1 → 200 "Welcome to nginx!"
curl http://localhost:8001/dc2/   # DC2 Traefik → web-dc2 → 200 "Welcome to nginx!"
```

Both routes worked with **zero manual Traefik configuration** — new
service registered in Consul → Traefik discovered and routed to it
automatically. Prometheus metrics enabled at `/metrics` on each instance's
`:8080`/`:8081` port; dashboard at the same.

---

## Phase 6 — NATS: Pub-Sub Messaging

Simple fire-and-forget pub-sub — no persistent log, no queue by default
(the opposite pattern from Kafka/RabbitMQ):

```bash
docker compose up -d nats
docker exec nomad-dc1-server nomad run /nomad/jobs/nats-subscriber.nomad.hcl
docker exec nomad-dc1-server nomad run /nomad/jobs/nats-publisher.nomad.hcl
```

**Result — 46+ events exchanged, one every 5s:**
```
[notification-service] New order received: {'order_id': 1, 'item': 'phone', ...}
[notification-service] Sending notification for order #1 (phone)
...
[notification-service] New order received: {'order_id': 46, 'item': 'phone', ...}
```

### JetStream (optional persistence layer)

```bash
docker run --rm --network hashinet natsio/nats-box:latest \
  nats stream add ORDERS --server=nats://nats:4222 \
  --subjects="order-created" --storage=file --retention=limits \
  --max-msgs=1000 --max-age=1h --replicas=1 --defaults
```

**Result:** stream persisted messages to disk independent of subscriber
connectivity (`Storage: File`, message count climbing: 8 → 9 → ...).

**When to use plain pub-sub vs JetStream vs Kafka** — full trade-off
write-up in
[`docs/nats-jetstream-tradeoff.md`](docs/nats-jetstream-tradeoff.md).
Short version: Kafka's operational cost (ZooKeeper/KRaft, partitions,
broker tuning) is often unjustified for internal notifications or cache
invalidation — NATS lets you opt into durability per-subject instead of
committing to a heavyweight platform for every message type.

---

## Phase 7 — DC1 Failure Test

```bash
docker stop consul-dc1-server nomad-dc1-server nomad-dc1-client
```

### What survived

| Check | Result |
|---|---|
| Consul WAN gossip detects failure | `consul-dc1-server.dc1` → `failed` within ~40s, no manual step |
| DC2 Traefik keeps serving | `curl localhost:8001/dc2/` → 200 OK, unaffected |
| `web-dc2` (DC2-only job) | Fully unaffected — never touches DC1 |

### What did NOT survive (and why — the real lesson)

- **`web-dc1`** — down with DC1's client. Expected: it's *hard-constrained*
  to `dc1`. A hard DC constraint exists precisely so a workload does NOT
  silently move elsewhere (data residency, latency-sensitive DB proximity,
  etc.) — this is correct behavior, not a failure.
- **`agent-anywhere`** (the "either DC" job) — did **not** auto-reschedule
  to DC2. Root cause: **the two Nomad server clusters in this lab are
  independent, non-federated Raft clusters** — only Consul is WAN-joined.
  `nomad server members` on DC2 shows only `nomad-dc2-server.global`,
  never DC1. In a real multi-region Nomad deployment, Nomad servers
  themselves are federated (`nomad server join`), giving a single control
  plane that can reschedule cross-DC. This lab's Nomad layer is two
  separate single-DC islands glued together only by Consul.

Full write-up with all evidence:
[`docs/dc1-failure-test.md`](docs/dc1-failure-test.md).

After the test, DC1 was restarted and fully rejoined:
```bash
docker start consul-dc1-server nomad-dc1-server nomad-dc1-client
# consul-dc1-server.dc1 → alive again
# nomad-dc1-client → ready again
```

---

## Nomad vs Kubernetes — When You'd Pick Each

| | **Nomad** | **Kubernetes** |
|---|---|---|
| Workload types | Containers **and** raw binaries/VMs/Java in one scheduler | Containers only |
| Learning curve | Single binary, HCL job specs, minimal moving parts | etcd, kubelet, kube-proxy, CNI, controllers — much larger surface |
| Service mesh | Consul Connect (opt-in, lightweight sidecars) | Usually Istio/Linkerd — heavier, more opinionated |
| Multi-region | Federate Nomad servers explicitly (`server join`) | Federation is a bigger architectural decision (multi-cluster tooling) |
| Ecosystem/tooling | Smaller — fewer third-party operators/Helm-chart equivalents | Enormous — Helm, operators, almost anything has a chart |
| Best fit | Mixed fleets (VMs + containers + legacy binaries), teams wanting operational simplicity, edge/on-prem with limited ops headcount | Container-native orgs, teams needing the ecosystem, complex autoscaling/multi-tenant needs |

**Pick Nomad when:** you have non-containerized workloads to run
alongside containers, you want a single small binary instead of a
control-plane stack, or your team is small and doesn't want to own etcd/
kube-apiserver operational complexity.

**Pick Kubernetes when:** you're all-in on containers, you need the vast
ecosystem (operators, service meshes, autoscalers), or your org already
has K8s expertise and tooling investment.

Almost nobody has hands-on Nomad experience — this project (including its
failure modes) is a stronger interview signal than another "I ran
`kubectl apply`" project.

---

## Known Limitations Summary

1. **Consul Connect mTLS sidecar** — blocked by a Docker-in-container
   filesystem race condition, not a config/understanding gap. See
   [`docs/consul-connect-limitation.md`](docs/consul-connect-limitation.md).
2. **Cross-DC Nomad job rescheduling** — requires federated Nomad servers,
   which this lab's two-independent-clusters setup does not have. See
   [`docs/dc1-failure-test.md`](docs/dc1-failure-test.md) for the fix
   (`nomad server join`) that would close this gap in a real deployment.

Both limitations are root-caused with evidence, not just noted — that
diagnostic trail is itself part of the deliverable.

---

## Quick Reference — All Commands

```bash
# Bring everything up
docker compose up -d

# Inject Vault token locally after any Vault restart
./scripts/inject-vault-token.sh

# Commit safely (never leaks the Vault token)
./scripts/safe-commit.sh "your message"

# Check cluster health
docker exec nomad-dc1-server nomad node status
docker exec nomad-dc2-server nomad node status
docker exec consul-dc1-server consul members -wan

# Job status
docker exec nomad-dc1-server nomad job status
docker exec nomad-dc2-server nomad job status
```
