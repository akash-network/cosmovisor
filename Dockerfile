FROM golang as builder

ARG VERSION=v1.3.0

RUN \
    GOBIN=/usr/bin go install github.com/schwarzit/go-template/cmd/gt@latest \
 && GOBIN=/usr/bin go install github.com/cosmos/cosmos-sdk/cosmovisor/cmd/cosmovisor@${VERSION}

FROM debian:bullseye
LABEL "org.opencontainers.image.source"="https://github.com/16psyche/cosmovisor"

ENV LANG="en_US.UTF-8"
ARG TARGETARCH

RUN \
    apt-get update \
 && apt-get install -y --no-install-recommends \
    tini \
    curl \
    wget \
    jq \
    ca-certificates \
    unzip \
    gzip \
    libarchive-tools \
    netcat \
    gettext-base \
    build-essential \
    git \
 && rm -rf /var/lib/apt/lists/*

RUN wget -qO- https://go.dev/dl/go1.19.1.linux-$TARGETARCH.tar.gz | tar -C /usr/local -xzf -

ENV PATH=$PATH:/usr/local/go/bin

COPY --from=builder /usr/bin/cosmovisor /usr/bin/cosmovisor
COPY --from=builder /usr/bin/gt /usr/bin/gt
COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
