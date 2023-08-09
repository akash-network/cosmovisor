#!/usr/bin/env bash

shopt -s dotglob

set_x=${SHELL_SET_X:-false}
set_e=${SHELL_SET_E:-true}
set_u=${SHELL_SET_U:-true}
set_pipefail=${SHELL_SET_PIPEFAIL:-false}

unset CHAIN_IMPORT_GENESIS
unset CHAIN_UNSAFE_RESET_ALL
unset SHELL_SET_PIPEFAIL

import_genesis=${CONFIG_FORCE_IMPORT_GENESIS:-false}
reset_data=${CONFIG_RESET_DATA:-false}
binary_url=${CONFIG_BINARY_URL:-}
try_compile=${CONFIG_TRY_COMPILE_BINARY:-false}
addrbook_url=${CONFIG_ADDRBOOK_URL:-}
peer_validation=${CONFIG_PEER_VALIDATION:-false}
overwrite_seeds=${CONFIG_OVERWRITE_SEEDS:-false}
snapshot_url=${CONFIG_SNAPSHOT_URL:-}
snapshot_dl=${CONFIG_SNAPSHOT_DL:-false}

CONFIG_WASM_PATH=${CONFIG_WASM_PATH:-wasm}

CONFIG_S3_KEY=${CONFIG_S3_KEY:-}
CONFIG_S3_SECRET=${CONFIG_S3_SECRET:-}
CONFIG_S3_ENDPOINT="${CONFIG_S3_ENDPOINT:-https://s3.filebase.com}"
CONFIG_S3_PATH=${CONFIG_S3_PATH:-}
CONFIG_GPG_KEY_PASSWORD="${CONFIG_GPG_KEY_PASSWORD:-}"
CONFIG_S3_ALWAYS_DL="${CONFIG_S3_ALWAYS_DL:=false}"

unset CONFIG_IMPORT_GENESIS
unset CONFIG_UNSAFE_RESET_ALL
unset CONFIG_DOWNLOAD_RECOMMENDED_BINARY
unset CONFIG_PEER_VALIDATION
unset CONFIG_SNAPSHOT_URL
unset CONFIG_SNAPSHOT_HAS_DATA_DIR
unset CONFIG_SNAPSHOT_DL
unset CHAIN_INIT

UNSAFE_SKIP_BACKUP=${UNSAFE_SKIP_BACKUP:-false}

CHAIN_STATESYNC_ENABLE=${CHAIN_STATESYNC_ENABLE:-false}
CHAIN_STATESYNC_RPC_SERVERS=${CHAIN_STATESYNC_RPC_SERVERS:-}

GO_VERSION=${GO_VERSION:-"1.19.2"}

export AWS_ACCESS_KEY_ID=$CONFIG_S3_KEY
export AWS_SECRET_ACCESS_KEY=$CONFIG_S3_SECRET

if [[ -n $CONFIG_S3_ENDPOINT ]]; then
    s3_uri_base="s3://${CONFIG_S3_BUCKET}/${CONFIG_S3_PATH}"
    aws_args="--endpoint-url ${CONFIG_S3_ENDPOINT}"
fi

function blank_data() {
    mkdir -p "$CHAIN_HOME"/data
    echo "{\"height\":\"0\",\"round\": 0,\"step\": 0}" >"$CHAIN_HOME/data/priv_validator_state.json"
}

restore_key() {
    local file="$1"

    if [ -n "$CONFIG_GPG_KEY_PASSWORD" ]; then
        file+=".gpg"
    fi

    if [[ -z $CONFIG_S3_ENDPOINT ]]; then
        return
    fi

    # shellcheck disable=SC2086
    aws ""$aws_args s3api head-object --bucket "${CONFIG_S3_BUCKET}" --key "${CONFIG_S3_PATH}/$file" >/dev/null 2>&1

    # shellcheck disable=SC2086
    if aws $aws_args s3api head-object --bucket "${CONFIG_S3_BUCKET}" --key "${CONFIG_S3_PATH}/$file" >/dev/null 2>&1 ; then
        echo "restoring $file"
        rm -f $2/$file
        aws $aws_args s3 cp "${s3_uri_base}/$file" $2/$file --only-show-errors

        if [[ $file == *.gpg ]]; then
            echo "decrypting $file"
            echo "$CONFIG_GPG_KEY_PASSWORD" | gpg --decrypt --batch --passphrase-fd 0 "$2/$file" >"$2/$1"
            rm "$2/$file"
        fi
    else
        echo "$1 backup not found"
    fi
}

function content_size() {
    size_in_bytes=$(wget "$1" --spider --server-response -O - 2>&1 | sed -ne '/Content-Length/{s/.*: //;p}')
    case "$size_in_bytes" in
        # Value cannot be started with `0`, and must be integer
    [1-9]*[0-9])
        echo "$size_in_bytes"
        ;;
    esac
}

function content_name() {
    name=$(wget "$1" --spider --server-response -O - 2>&1 | grep "Content-Disposition:" | tail -1 | awk -F"filename=" '{print $2}')
    # shellcheck disable=SC2181
    [ $? -ne 0 ] && exit 1
    echo "$name"
}

function content_type() {
    case "$1" in
        *.tar.cz)
            tar_cmd="tar -xJ -"
            ;;
        *.tar.gz)
            tar_cmd="tar xzf -"
            ;;
        *.tar.lz4)
            tar_cmd="lz4 -d | tar xf -"
            ;;
        *.tar.zst)
            tar_cmd="zstd -cd | tar xf -"
            ;;
        *)
            tar_cmd="tar xf -"
            ;;
    esac

    echo "$tar_cmd"
}

if [[ ${set_x} == "true" ]]; then
    set -x
else
    set +x
fi

if [[ ${set_e} == "true" ]]; then
    set -e
else
    set +e
fi

if [[ ${set_pipefail} == "true" ]]; then
    set -o pipefail
fi

trap 'echo >&2 "Error - exited with status $? at line $LINENO:"; pr -tn $0 | tail -n+$((LINENO - 3)) | head -n7 >&2' ERR

function usage() {
    echo "
supported values to the CHAIN env variable
    - akash
    - rebus
    - stride
    - osmosis
"
    exit 1
}

if [[ ${CHAIN_STATESYNC_ENABLE} == true && -z ${CHAIN_STATESYNC_RPC_SERVERS} ]]; then
    echo "CHAIN_STATESYNC_RPC_SERVERS is not set"
    exit 1
fi

config_url=${CHAIN_JSON:-}

if [[ -z $config_url ]]; then
    # shellcheck disable=SC2153
    case "${CHAIN}" in
        akash)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/akash/chain.json
            ;;
        stride)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/stride/chain.json
            ;;
        rebus)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/rebus/chain.json
            ;;
        osmosis)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/osmosis/chain.json
            ;;
        "")
            echo "CHAIN is not set"
            usage
            ;;
        *)
            echo "unsupported chain: $CHAIN"
            usage
            ;;
    esac
fi

unset CHAIN
unset CHAIN_JSON

if [[ ${set_u} == "true" ]]; then
    set -u
else
    set +u
fi

tmpfile() {
    mktemp "/tmp/$(basename "$0").XXXXXX"
}

chain_metadata=$(tmpfile)

trap 'rm -f $chain_metadata' EXIT

curl -sSfl "$config_url" >"$chain_metadata"

chain="$(jq -Mr '.chain_name' "$chain_metadata")"
echo "fetching chain info for $chain"

DAEMON_NAME="$(jq -Mr '.daemon_name' "$chain_metadata")"

ENV_PREFIX=${CONFIG_ENV_PREFIX:-"$(echo -n "${DAEMON_NAME}"_ | tr '[:lower:]' '[:upper:]')"}
unset CONFIG_ENV_PREFIX

if [[ ${ENV_PREFIX: -1} != "_" ]]; then
    ENV_PREFIX=${ENV_PREFIX}_
fi

function echo_dname() {
    varname=$1
    echo "$1"
}

function echo_dval() {
    echo "${!1}"
}

CHAIN_HOME=${CHAIN_HOME:-"$(jq -Mr '.node_home' "$chain_metadata")"}
# "or" condition after the head command is to filter out SIGPIPE error code
# shellcheck disable=SC2002
CHAIN_MONIKER=${CHAIN_MONIKER:-$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w "${1:-20}" | head -n 1 || (
    ec=$?
    if [ "$ec" -eq 141 ]; then exit 0; else exit "$ec"; fi
))}

# if default path is in use it will be in format $HOME/.<daemon_name> so env needs to be evaluated
CHAIN_HOME="$(echo "${CHAIN_HOME}" | envsubst)"
CHAIN_CHAIN_ID=${CHAIN_ID:-$(jq -Mr '.chain_id' "$chain_metadata")}
unset CHAIN_ID

chain_version=${CHAIN_VERSION:-}
unset CHAIN_VERSION

chain_genesis_file="$CHAIN_HOME/config/genesis.json"
chain_config_dir="$CHAIN_HOME/config"
chain_config="$chain_config_dir/config.toml"
#chain_app_config="$chain_config_dir/app.toml"

cosmovisor_genesis="$CHAIN_HOME/cosmovisor/genesis"
cosmovisor_current="$CHAIN_HOME/cosmovisor/current"
cosmovisor_current_bin="$cosmovisor_current/bin"

data_dir="${CHAIN_HOME}/data"
wasm_dir="${CHAIN_HOME}/${CONFIG_WASM_PATH}"

[[ -f /boot/prerun1.sh ]] && /boot/prerun1.sh

if [[ ! -f "$cosmovisor_genesis/bin/$DAEMON_NAME" ]]; then
    mkdir -p "$cosmovisor_genesis/bin"
fi

if [[ ! -e "$cosmovisor_current" ]]; then
    ln -snf "$cosmovisor_genesis" "$cosmovisor_current"
fi

if [ ! -f "$cosmovisor_current_bin/$DAEMON_NAME" ]; then
    binary_path=$(readlink -f "${cosmovisor_current_bin}")
    uname_arch=$(uname -m | sed -e "s/x86_64/amd64/g" -e "s/aarch64/arm64/g")

    if [[ -z "$binary_url" ]]; then
        echo "CONFIG_BINARY_URL is empty. trying to find recommended binary in the chain metadata"

        if [[ -n "$chain_version" ]]; then
            binary_url=$(jq -eMr --arg version "$chain_version" --arg mach "linux/$uname_arch" '.codebase.versions[] | select(.name == $version) | .binaries | select(.[$mach] != null) | .[$mach]' "$chain_metadata")
            exit_result=$?
            if [ $exit_result -ne 0 ]; then
                echo "\"linux/$uname_arch\" binary for chain version $chain_version is not present in chain metadata"
                exit $exit_result
            fi
        else
            binary_url=$(jq -eMr --arg mach "linux/$uname_arch" '.codebase.binaries | select(.[$mach] != null) | .[$mach]' "$chain_metadata")
            exit_result=$?
            if [ $exit_result -ne 0 ]; then
                echo "\"linux/$uname_arch\" binary for chain version $chain_version is not present in chain metadata"
                exit $exit_result
            fi
        fi
    fi

    if [[ -n "$binary_url" ]]; then
        echo "downloading binary ${DAEMON_NAME} from $binary_url"
        go-getter -mode=file "${binary_url}" "${binary_path}/${DAEMON_NAME}"
    elif [[ $try_compile == true ]]; then
        echo "trying to compile binary for linux/$uname_arch"

        if ! command -v go &> /dev/null ; then
            echo "go has not been found. installing go$GO_VERSION"
            go_url="https://go.dev/dl/go${GO_VERSION}.linux-${uname_arch}.tar.gz"

            pv_args="-petrafb"
            sz=$(content_size "$go_url")
            if [[ -n $sz ]]; then
                pv_args+=" -s $sz"
            fi

            # shellcheck disable=SC2086
            (wget -qO- "$go_url" | pv $pv_args | tar -C /usr/local -xzf -) 2>&1 | stdbuf -o0 tr '\r' '\n'

            export PATH=$PATH:/usr/local/go/bin
        fi

        git_repo=$(jq -Mr '.codebase.git_repo' "$chain_metadata")
        recommended_version=$(jq -Mr '.codebase.recommended_version' "$chain_metadata")
        pushd "$(pwd)"
        mkdir src && cd src
        git config --global advice.detachedHead false
        git clone --branch "${recommended_version}" --depth 1 "${git_repo}" .

        if [[ -d /config/patches/${DAEMON_NAME}/${recommended_version} ]]; then
            for patch in /config/patches/"${DAEMON_NAME}"/"${recommended_version}"/*; do
                git apply "$patch"
            done
        fi

        GOBIN=${binary_path} make install

        popd
        rm -rf src
    else
        echo "unable to find precompiled binary for linux/$uname_arch"
        echo "set CONFIG_BINARY_URL"

        exit 1
    fi

    chmod +x "${cosmovisor_current_bin}/${DAEMON_NAME}"
fi

current_binary=$(readlink -f "${cosmovisor_current_bin}/${DAEMON_NAME}")

if [ ! -f "$chain_config" ]; then
    echo "initializing chain home dir $CHAIN_HOME"

    blank_data
    snapshot_dl=true

    "${current_binary}" init "${CHAIN_MONIKER}" --home "${CHAIN_HOME}" --chain-id="${CHAIN_CHAIN_ID}"

    import_genesis=true

    if [[ -n "$addrbook_url" ]]; then
        echo "downloading addrbook from $addrbook_url"
        go-getter -mod=file "$addrbook_url" "$chain_config_dir/addrbook.json"
    fi
elif [ ! -f "$chain_genesis_file" ]; then
    import_genesis=true
fi

if [[ "${import_genesis}" == "true" ]]; then
    # shellcheck disable=SC2002
    genesis_url=$(cat "${chain_metadata}" | jq -Mr '.codebase.genesis.genesis_url')
    genesis_url=$(curl -kIsL -w "%{url_effective}" -o /dev/null "$genesis_url")

    rm -f "$chain_genesis_file"
    echo "downloading chain genesis from ${genesis_url}"
    go-getter -mode=file "${genesis_url}" "$chain_genesis_file"
fi

if [[ "${reset_data}" == "true" ]]; then
    echo "cleaning data dir"
    rm -rf "${data_dir}"
    rm -rf "${wasm_dir}"

    blank_data
    snapshot_dl=true
elif [[ ! -d ${data_dir} ]] || ! find "$data_dir" -mindepth 1 -maxdepth 1 | read; then
    snapshot_dl=true
fi

if ! env | grep -q "^CHAIN_P2P_SEEDS"; then
    # shellcheck disable=SC2002
    if ! cat "${chain_metadata}" | jq -Mr '.peers.seeds[]' &>/dev/null; then
        echo "chain file does not contain seeds"
    else
        if [[ "$peer_validation" == "true" ]]; then
            echo "validating seeds"
        else
            echo "skipping seeds validation"
        fi

        seeds=
        while read -r id ip port; do
            if [[ "$peer_validation" == "true" ]]; then
                echo "validating seed: ${id}@${ip}:${port}"
                if timeout 1s nc -vz "${ip}" "${port}" >/dev/null 2>&1; then
                    echo "    PASS"
                    [[ "$seeds" == "" ]] && seeds=${id}@${ip}:${port} || seeds="$seeds,${id}@${ip}:${port}"
                else
                    echo "    FAIL"
                fi
            else
                [[ "$seeds" == "" ]] && seeds=${id}@${ip}:${port} || seeds="$seeds,${id}@${ip}:${port}"
            fi
        done <<<"$(cat "$chain_metadata" | jq -Mr '.peers.seeds[] | [.id, .address|gsub(":"; " ")] | @tsv')"
        declare CHAIN_P2P_SEEDS="$seeds"
    fi
else
    echo "CHAIN_P2P_SEEDS is set explicitly. ignoring chain seeds"
fi

if ! env | grep -q "^CHAIN_P2P_PERSISTENT_PEERS"; then
    # shellcheck disable=SC2002
    if ! cat "${chain_metadata}" | jq -Mr '.peers.persistent_peers[]' &>/dev/null; then
        echo "chain file does not contain persistent peers"
    else
        if [[ "$peer_validation" == "true" ]]; then
            echo "validating peers"
        else
            echo "skipping peers validation"
        fi

        peers=
        while read -r id ip port; do
            if [[ "$peer_validation" == "true" ]]; then
                echo "validating persistent peer: ${id}@${ip}:${port}"
                if timeout 1s nc -vz "${ip}" "${port}" >/dev/null 2>&1; then
                    echo "    PASS"
                    [[ "$peers" == "" ]] && peers=${id}@${ip}:${port} || peers="$peers,${id}@${ip}:${port}"
                else
                    echo "    FAIL"
                fi
            else
                [[ "$peers" == "" ]] && peers=${id}@${ip}:${port} || peers="$peers,${id}@${ip}:${port}"
            fi
        done <<<"$(cat "$chain_metadata" | jq -Mr '.peers.persistent_peers[] | [.id, .address|gsub(":"; " ")] | @tsv')"
        declare CHAIN_P2P_PERSISTENT_PEERS="$peers"
    fi
else
    echo "CHAIN_P2P_PERSISTENT_PEERS is set explicitly. ignoring chain persistent peers"
fi

set +u
if [[ -n ${ADDITIONAL_P2P_SEEDS+x} ]]; then
    echo "applying additional seeds"
    if [[ "${CHAIN_P2P_SEEDS}" == "" ]]; then
        CHAIN_P2P_SEEDS=${ADDITIONAL_P2P_SEEDS}
    else
        CHAIN_P2P_SEEDS="${CHAIN_P2P_SEEDS},${ADDITIONAL_P2P_SEEDS}"
    fi
    declare CHAIN_P2P_SEEDS
fi

if [[ -n ${ADDITIONAL_P2P_PERSISTENT_PEERS+x} ]]; then
    echo "applying additional persistent peers"
    if [[ "${CHAIN_P2P_PERSISTENT_PEERS}" == "" ]]; then
        CHAIN_P2P_PERSISTENT_PEERS=${ADDITIONAL_P2P_PERSISTENT_PEERS}
    else
        CHAIN_P2P_PERSISTENT_PEERS="${CHAIN_P2P_PERSISTENT_PEERS},${ADDITIONAL_P2P_PERSISTENT_PEERS}"
    fi
    declare CHAIN_P2P_PERSISTENT_PEERS

fi
set -u

unset ADDITIONAL_P2P_SEEDS
unset ADDITIONAL_P2P_PERSISTENT_PEERS

export CHAIN_P2P_SEEDS
export CHAIN_P2P_PERSISTENT_PEERS

if [ "${CHAIN_STATESYNC_ENABLE}" == true ]; then
    oIFS="$IFS"
    IFS=","
    # shellcheck disable=SC2206
    declare -a rpc_array=(${CHAIN_STATESYNC_RPC_SERVERS})
    IFS="$oIFS"
    unset oIFS

    # shellcheck disable=SC2206
    [[ ${#rpc_array[@]} -eq 1 ]] && rpc_array+=(${CHAIN_STATESYNC_RPC_SERVERS})

    unset CHAIN_STATESYNC_RPC_SERVERS

    height_diff=${BLOCK_HEIGHT_DIFF:-2000}

    LATEST_HEIGHT=$(curl -sL "${rpc_array[0]}/block" | jq -r .result.block.header.height)
    BLOCK_HEIGHT=$((LATEST_HEIGHT - height_diff))
    TRUST_HASH=$(curl -sL "${rpc_array[0]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)

    CHAIN_STATESYNC_RPC_SERVERS=${rpc_array[0]}

    for ((i = 1; i < ${#rpc_array[@]}; i++)); do
        test_hash=$(curl -sL "${rpc_array[i]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
        if [[ $TRUST_HASH != "${test_hash}" ]]; then
            echo "TRUST hash for block $BLOCK_HEIGHT does not match
    ${rpc_array[0]} : ${TRUST_HASH}
    ${rpc_array[i]} : ${test_hash}
"
            exit 1
        fi

        CHAIN_STATESYNC_RPC_SERVERS="${CHAIN_STATESYNC_RPC_SERVERS},${rpc_array[i]}"
    done

    export CHAIN_STATESYNC_RPC_SERVERS
    export CHAIN_STATESYNC_TRUST_HEIGHT=${BLOCK_HEIGHT}
    export CHAIN_STATESYNC_TRUST_HASH=${TRUST_HASH}
fi

# Overwrite seeds in config.toml for chains that are not using the env variable correctly
if [ "$overwrite_seeds" == "true" ] && [ -n "$CHAIN_P2P_SEEDS" ]; then
    echo "overwriting seeds"
    sed -i "s/seeds = \"\"/seeds = \"$CHAIN_P2P_SEEDS\"/" "$chain_config"
fi

# Snapshot
if [ "$snapshot_dl" == true ]; then
    if [ -n "${snapshot_url}" ]; then
        rm -rf "$data_dir"
        pushd "$(pwd)"

        mkdir -p "$data_dir"
        cd "$data_dir"

        if [[ "${snapshot_url}" =~ ^https?:\/\/.* ]]; then
            echo "Downloading snapshot to [$(pwd)] from $snapshot_url..."

            # Detect content size via HTTP header `Content-Length`
            # Note that the server can refuse to return `Content-Length`, or the URL can be incorrect
            pv_args="-petrafb -i 5"
            sz=$(content_size "$snapshot_url")
            if [[ -n $sz ]]; then
                pv_args+=" -s $sz"
            fi

            name=$(content_name "$snapshot_url")

            tar_cmd=$(content_type "$name")

            # shellcheck disable=SC2086
            (wget -nv -O - "$snapshot_url" | pv $pv_args | eval " $tar_cmd") 2>&1 | stdbuf -o0 tr '\r' '\n'
        else
            echo "Unpacking snapshot to [$(pwd)] from $snapshot_url..."

            tar_cmd=$(content_type "$snapshot_url")

            # shellcheck disable=SC2086
            (pv -petrafb -i 5 "$snapshot_url" | eval "$tar_cmd") 2>&1 | stdbuf -o0 tr '\r' '\n'
        fi

        # if snapshot provides data dir then move all things up
        if [[ -d data ]]; then
            echo "snapshot has data dir. moving content..."
            mv data/* ./

            rm -rf data
        fi
        popd
    else
        echo "Snapshot URL not found"
    fi
fi

# Restore keys
if [[ -n "$CONFIG_S3_PATH" ]] && [[ ! -f "$CHAIN_HOME/.keys" || "${CONFIG_S3_ALWAYS_DL}" == "true" ]]; then
    restore_key "node_key.json" "$chain_config_dir"
    restore_key "priv_validator_key.json" "$chain_config_dir"
    touch "$CHAIN_HOME/.keys"
fi

DAEMON_HOME=${CHAIN_HOME}

while IFS="=" read -r var val; do
    # shellcheck disable=SC2001
    varname=$(echo "${var}" | sed -e "s/^CHAIN_/$ENV_PREFIX/")
    unset "${var}"
    declare "${varname}"="${val}"
    # shellcheck disable=SC2163
    export "${varname}"
done <<<"$(env | grep ^"CHAIN_")"

export UNSAFE_SKIP_BACKUP
export DAEMON_NAME
export DAEMON_HOME

env | sort | grep -q "^CHAIN_" && echo "some env variable starting with CHAIN_ have not been unset" && exit 1

echo "dump current environment variables..."
echo ""
echo "app env..."
env | sort | grep "^DAEMON_"
echo ""
env | sort | grep "^${ENV_PREFIX}"
echo ""
echo "other env..."
env | sort | grep -v "^${ENV_PREFIX}\|^DAEMON_"
echo ""
[[ -f /boot/prerun2.sh ]] && /boot/prerun2.sh

exec cosmovisor run start |& grep --line-buffered -vi 'peer'
