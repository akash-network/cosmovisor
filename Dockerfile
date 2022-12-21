ARG GOLANG_VERSION=1.19.2

FROM golang:${GOLANG_VERSION}-bullseye AS base

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
 && wget -qO- https://go.dev/dl/go$GOLANG_VERSION.linux-$TARGETARCH.tar.gz | tar -C /usr/local -xzf - \
 && export AWS_ARCH=$(echo $TARGETARCH | sed -e "s/amd64/x86_64/g" -e "s/arm64/aarch64/g") \
 && curl "https://awscli.amazonaws.com/awscli-exe-linux-$AWS_ARCH.zip" -o "awscliv2.zip" \
 && unzip awscliv2.zip \
 && ./aws/install \
 && rm -rf awscliv2.zip \
 && git config --global advice.detachedHead "false"

#ENV PATH=$PATH:/usr/local/go/bin

FROM base AS build
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

COPY --from=build /usr/bin/cosmovisor /usr/bin
COPY --from=build /usr/bin/gt /usr/bin
COPY --from=build /usr/bin/go-getter /usr/bin

COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
