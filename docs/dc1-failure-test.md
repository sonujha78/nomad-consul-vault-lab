# Multi-Datacenter Failure Test — DC1 Down

## What was stopped
docker stop consul-dc1-server nomad-dc1-server nomad-dc1-client
This simulates DC1 going down entirely — its Consul agent, Nomad server,
and Nomad client all offline simultaneously.

## What survived (as expected)

### 1. Consul WAN gossip correctly detected the failure
Node Status DC
consul-dc1-server.dc1 failed dc1
consul-dc2-server.dc2 alive dc2
Consul's SWIM-based gossip protocol marked `consul-dc1-server` as `failed`
within ~40 seconds — no manual intervention. `consul catalog datacenters`
continued returning both DCs (DC1 remains a known-but-unreachable DC, which
is correct — Consul doesn't remove a DC from the catalog just because it's
unreachable, since it could recover).

### 2. Traefik (DC2 instance) continued serving traffic unaffected
curl http://localhost:8001/dc2/ → 200 OK, "Welcome to nginx!"
Because this lab runs **per-DC Traefik instances** (a deliberate design
choice after discovering Traefik's Consul Catalog provider doesn't do
cross-DC catalog queries even with WAN federation — see traefik phase
notes), DC2's Traefik was never dependent on DC1 and kept routing without
any change.

### 3. web-dc2 (DC2-constrained job) was completely unaffected
It runs on `nomad-dc2-client`, registered in `consul-dc2-server` — neither
of which touch DC1 at all. Zero impact, as expected for a properly isolated
DC2 workload.

## What did NOT survive (and why — this is the real DR lesson)

### web-dc1 and anything scheduled on DC1
Went down with DC1's Nomad client. Expected: this job is hard-constrained
to `dc1` (`constraint { attribute = "${node.datacenter}" value = "dc1" }`).
Nomad has no DC2 fallback for a hard-constrained job — that's the entire
point of a hard constraint. This is correct, intentional behavior, not a
bug: you use a hard DC constraint precisely when a workload MUST run in a
specific location (data residency, latency to a specific DB, etc.) and
should NOT silently move elsewhere.

### agent-anywhere (the "either DC" job) did NOT reschedule to DC2
This is the most important finding of the whole test, and it reveals a
real architectural limitation of this lab setup:

**Nomad servers in this lab are two independent, non-federated Nomad
clusters** — `nomad-dc1-server` and `nomad-dc2-server` each run their own
Raft consensus and have no knowledge of each other's jobs or nodes
(`nomad server members` on dc2 shows only `nomad-dc2-server.global`, never
dc1). Only **Consul** is WAN-federated between the two DCs.

In a real production Nomad multi-region setup, Nomad servers themselves
are federated (via `nomad server join` across regions/DCs), so a job with
`datacenters = ["dc1", "dc2"]` is scheduled by a single federated Nomad
control plane that can reschedule across DCs if one goes down.

This lab's Nomad layer is **two separate single-DC clusters glued together
only by shared Consul service discovery and per-DC Traefik ingress** — not
a single federated Nomad deployment. That's a meaningful architectural
difference worth calling out explicitly:

- Consul's job (service discovery, health, WAN gossip) worked exactly as
  designed and survived the DC1 outage cleanly.
- Nomad's job (scheduling/rescheduling across DCs) requires federated
  Nomad servers, which this lab does not have — each DC's Nomad is its own
  island. To get true "either-DC" auto-rescheduling like the task
  describes, the next iteration of this lab would need
  `nomad server join <dc2-server-ip>` between the two Nomad server
  clusters (or equivalent Nomad Enterprise multi-region setup).

## Interview takeaway
This distinction — **Consul federation vs Nomad federation being two
separate concerns** — is exactly the kind of nuance that shows real
hands-on understanding rather than surface-level familiarity. Many
tutorials gloss over this because they only set up single-DC Nomad; running
into it here, diagnosing it via `nomad server members`, and explaining the
fix (`nomad server join`) is a stronger signal than if everything had
"just worked."
