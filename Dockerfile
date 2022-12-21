ARG GO_VERSION
ARG TARGETARCH

FROM debian:bullseye AS base

ENV LANG="en_US.UTF-8"
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
 && curl https://dl.min.io/client/mc/release/linux-$TARGETARCH/mc -o /usr/bin/mc \
 && chmod +x /usr/bin/mc \
 && git config --global advice.detachedHead "false"

FROM golang:${GO_VERSION}-bullseye as build

ARG GO_VERSION
ARG GO_GETTER_VERSION
ARG COSMOVISOR_VERSION

ENV GO111MODULE=on
ENV GOPROXY=https://proxy.golang.org,direct

SHELL ["/bin/bash", "-c"]

RUN git config --global advice.detachedHead "false"

RUN GOBIN=/usr/bin go install github.com/schwarzit/go-template/cmd/gt@latest

RUN GOBIN=/usr/bin go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v${COSMOVISOR_VERSION}

RUN \
    git clone -b $GO_GETTER_VERSION --depth 1 https://github.com/hashicorp/go-getter \
 && cd go-getter/cmd/go-getter \
 && GOBIN=/usr/bin go install

FROM base
LABEL "org.opencontainers.image.source"="https://github.com/16psyche/cosmovisor"

ARG GO_VERSION
ENV GO_VERSION=$GO_VERSION

COPY --from=build /usr/bin/cosmovisor /usr/bin
COPY --from=build /usr/bin/gt /usr/bin
COPY --from=build /usr/bin/go-getter /usr/bin

COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
