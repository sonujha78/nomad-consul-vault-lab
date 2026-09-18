FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        iptables \
        iproute2 \
        curl \
        unzip \
        ca-certificates \
        docker.io \
    && rm -rf /var/lib/apt/lists/*

ARG NOMAD_VERSION=1.8.4
RUN curl -fsSL https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip -o /tmp/nomad.zip && \
    unzip -o /tmp/nomad.zip -d /usr/local/bin && \
    rm /tmp/nomad.zip && \
    chmod +x /usr/local/bin/nomad

ARG CONSUL_VERSION=1.19.2
RUN curl -fsSL https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -o /tmp/consul.zip && \
    unzip -o /tmp/consul.zip -d /usr/local/bin && \
    rm /tmp/consul.zip && \
    chmod +x /usr/local/bin/consul

ENTRYPOINT ["nomad"]
