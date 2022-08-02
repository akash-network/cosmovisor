FROM golang as builder

ARG VERSION=v1.2.0

RUN \
    GOBIN=/usr/bin go install github.com/schwarzit/go-template/cmd/gt@latest \
 && git clone https://github.com/cosmos/cosmos-sdk \
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
    gettext-base \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/bin/cosmovisor /usr/bin/cosmovisor
COPY --from=builder /usr/bin/gt /usr/bin/gt
COPY ./scripts/entrypoint.sh /entrypoint.sh

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
