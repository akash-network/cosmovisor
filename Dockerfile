ARG GOLANG_VERSION=1.19.2

FROM debian:bullseye AS base

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
    pv \
    lz4 \
 && rm -rf /var/lib/apt/lists/* \
 && git config --global advice.detachedHead "false" \
 && curl https://dl.min.io/client/mc/release/linux-$TARGETARCH/mc -o /usr/bin/mc \
 && chmod +x /usr/bin/mc

FROM golang:${GOLANG_VERSION}-bullseye as build
ARG GO_GETTER_VERSION=v2.1.1
ARG VERSION=v1.4.0

SHELL ["/bin/bash", "-c"]

RUN GOBIN=/usr/bin go install github.com/schwarzit/go-template/cmd/gt@latest
RUN GOBIN=/usr/bin go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@${VERSION}
RUN \
    git clone -b $GO_GETTER_VERSION --depth 1 https://github.com/hashicorp/go-getter \
 && cd go-getter/cmd/go-getter \
 && GOBIN=/usr/bin go install

FROM base
LABEL "org.opencontainers.image.source"="https://github.com/16psyche/cosmovisor"

ENV GOLANG_VERSION=$GOLANG_VERSION

COPY --from=build /usr/bin/cosmovisor /usr/bin
COPY --from=build /usr/bin/gt /usr/bin
COPY --from=build /usr/bin/go-getter /usr/bin

COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
