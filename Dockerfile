ARG COSMOVISOR_VERSION
FROM ghcr.io/akash-network/cosmovisor-base:$COSMOVISOR_VERSION as cosmovisor

FROM ubuntu:jammy AS base
LABEL "org.opencontainers.image.source"="https://github.com/akash-network/cosmovisor"

ARG TARGETARCH
ARG GO_GETTER_VERSION
ARG GO_TEMPLATE_VERSION

SHELL ["/bin/bash", "-c"]

ENV LANG="en_US.UTF-8"

RUN \
    apt-get update \
 && apt-get install -y --no-install-recommends \
    jq \
    pv \
    lz4 \
    git \
    tini \
    curl \
    wget \
    gzip \
    unzip \
    netcat \
    gettext-base \
    build-essential \
    ca-certificates \
    libarchive-tools \
 && rm -rf /var/lib/apt/lists/*

RUN \
    AWSCLI_ARCH=$(echo -n $TARGETARCH | sed -e 's/arm64/aarch64/g' | sed -e 's/amd64/x86_64/g') \
 && wget -q "https://awscli.amazonaws.com/awscli-exe-linux-${AWSCLI_ARCH}.zip" -O awscli.zip \
 && unzip awscli.zip && rm awscli.zip \
 && ./aws/install \
 && rm -r aws

RUN \
    git config --global advice.detachedHead "false" \
 && wget https://github.com/SchwarzIT/go-template/releases/download/${GO_TEMPLATE_VERSION}/gt-linux-${TARGETARCH} -O /usr/bin/gt \
 && chmod +x /usr/bin/gt \
 && wget https://github.com/troian/go-getter/releases/download/${GO_GETTER_VERSION}/go-getter_linux_${TARGETARCH}.deb -O go-getter.deb \
 && dpkg -i go-getter.deb \
 && rm -f go-getter.deb

ARG GOVERSION
ENV GOVERSION=$GOVERSION

COPY --from=cosmovisor /usr/bin/cosmovisor /usr/bin
COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
