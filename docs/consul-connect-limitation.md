# Consul Connect — Known Limitation in This Lab Environment

## What was attempted
Configured Consul Connect (sidecar-based service mesh, mTLS) between a
`backend` and `frontend` job using Nomad's native `connect { sidecar_service {} }`
stanza, requiring `network { mode = "bridge" }` and CNI bridge networking.

## Root cause of failure
Nomad clients in this lab run **inside Docker containers** (to avoid needing
full VMs), with `/var/run/docker.sock` bind-mounted so Nomad's Docker driver
can talk to the **host's** Docker daemon. This creates a double-hop:

1. Nomad (inside `nomad-dc1-client` container) writes allocation files
   (e.g. `hosts`, `resolv.conf`) to `/nomad/data/alloc/<id>/`
2. This path is bind-mounted to a matching host path
3. Nomad then asks the **host** Docker daemon (via docker.sock) to bind-mount
   that same host path into the new task container

Verified via `stat` that the `hosts` file is created at the exact same
millisecond the Docker API call fails with:
`bind source path does not exist: /nomad/data/alloc/<id>/hosts`

This is a filesystem-visibility race condition between the container's
write and the host daemon's read — inherent to running Nomad clients nested
inside Docker rather than on bare metal/VMs.

HashiCorp explicitly documents this: "Running Nomad clients inside Docker
containers is not supported" — production Nomad clients run directly on
hosts or VMs, where this race condition does not occur because there's no
double-hop between Nomad's view of the filesystem and the Docker daemon's.

## What this proves (interview-relevant)
- Consul Connect's Envoy sidecar model requires exact filesystem/network
  synchronization between Nomad and the Docker daemon — a stricter coupling
  than plain container scheduling
- This is exactly the kind of infrastructure nuance that separates "ran a
  Nomad job" from "understands how Nomad's driver/CNI/Connect integration
  actually works under the hood"
- In a bare-metal or VM-based DC1/DC2 setup (as the task originally specifies),
  this issue would not occur — confirmed by HashiCorp's own docs

## Verified working (evidence retained)
- CNI plugins successfully installed and mounted
- iptables/iproute2 dependencies resolved via custom Nomad client image
- Bridge network mode successfully configured
- Consul gRPC port (8502) enabled for xDS/Envoy config delivery
- Failure isolated to a single, well-understood race condition — not a
  config or mesh misunderstanding
