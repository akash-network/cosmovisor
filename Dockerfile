FROM debian:bullseye
LABEL "org.opencontainers.image.source"="https://github.com/16psyche/cosmovisor"

ENV LANG="en_US.UTF-8"
ARG TARGETARCH
ARG GOLANG_VERSION=1.19.2
ARG GO_GETTER_VERSION=v2.1.1
ARG VERSION=v1.4.0

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
 && wget -qO- https://go.dev/dl/go$GOLANG_VERSION.linux-$TARGETARCH.tar.gz | tar -C /usr/local -xzf -

ENV PATH=$PATH:/usr/local/go/bin

SHELL ["/bin/bash", "-c"]

RUN \
    git config --global advice.detachedHead "false" \
 && GOBIN=/usr/bin go install github.com/schwarzit/go-template/cmd/gt@latest \
 && GOBIN=/usr/bin go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@${VERSION} \
 && git clone -b $GO_GETTER_VERSION --depth 1 https://github.com/hashicorp/go-getter \
 && pushd "$(pwd)" \
 && cd go-getter/cmd/go-getter \
 && GOBIN=/usr/bin go install \
 && popd \
 && rm -rf go-getter \
 && go clean -modcache \
 && export AWS_ARCH=$(echo $TARGETARCH | sed -e "s/amd64/x86_64/g" -e "s/arm64/aarch64/g") \
 && curl "https://awscli.amazonaws.com/awscli-exe-linux-$AWS_ARCH.zip" -o "awscliv2.zip" \
 && unzip awscliv2.zip \
 && ./aws/install \
 && rm -rf awscliv2.zip

COPY ./scripts/entrypoint.sh /entrypoint.sh
COPY ./patches/ /config/patches

ENTRYPOINT ["tini", "--"]
CMD ["/entrypoint.sh"]
