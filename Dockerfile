FROM golang as builder

ARG VERSION=v1.2.0

RUN \
    git clone https://github.com/cosmos/cosmos-sdk \
 && cd cosmos-sdk \
 && git checkout cosmovisor/$VERSION \
 && make cosmovisor \
 && cp cosmovisor/cosmovisor /usr/bin/cosmovisor

FROM debian:bullseye

LABEL "org.opencontainers.image.source"="https://github.com/16psyche/cosmovisor"

RUN \
    apt-get update \
 && apt-get install -y --no-install-recommends \
    tini \
    curl \
    jq \
    ca-certificates \
    unzip \
    gzip \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/bin/cosmovisor /usr/bin/cosmovisor

ENTRYPOINT ["tini", "--"]
CMD ["cosmovisor", "--help"]
