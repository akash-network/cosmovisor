#!/usr/bin/env bash

set_x=${SHELL_SET_X:-false}
set_e=${SHELL_SET_E:-true}
set_u=${SHELL_SET_U:-true}
set_pipefail=${SHELL_SET_PIPEFAIL:-false}

unset CHAIN_IMPORT_GENESIS
unset CHAIN_UNSAFE_RESET_ALL
unset SHELL_SET_PIPEFAIL

import_genesis=${CONFIG_FORCE_IMPORT_GENESIS:-false}
reset_data=${CONFIG_RESET_DATA:-false}
download_binary=${CONFIG_DOWNLOAD_RECOMMENDED_BINARY:-false}
peer_validation=${CONFIG_PEER_VALIDATION:-true}

unset CONFIG_IMPORT_GENESIS
unset CONFIG_UNSAFE_RESET_ALL
unset CONFIG_DOWNLOAD_RECOMMENDED_BINARY
unset CONFIG_PEER_VALIDATION

UNSAFE_SKIP_BACKUP=${UNSAFE_SKIP_BACKUP:-false}

CHAIN_STATESYNC_ENABLE=${CHAIN_STATESYNC_ENABLE:-false}
CHAIN_STATESYNC_RPC_SERVERS=${CHAIN_STATESYNC_RPC_SERVERS:-}

function blank_data() {
    mkdir -p $CHAIN_HOME/data
    echo "{\"height\":\"0\",\"round\": 0,\"step\": 0}" > "$CHAIN_HOME/data/priv_validator_state.json"
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
    - sifchain
    - rebus
    - stride
"
    exit 1
}

if [[ ${CHAIN_STATESYNC_ENABLE} == true && -z ${CHAIN_STATESYNC_RPC_SERVERS} ]]; then
    echo "CHAIN_STATESYNC_RPC_SERVERS is not set"
    exit 1
fi

config_url=${CONFIG_URL:-}

if [[ ! -n $config_url ]]; then
    case "${CHAIN}" in
        akash)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/akash/chain.json
            ;;
        sifchain)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/sifchain/chain.json
            ;;
        stride)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/stride/chain.json
            ;;
        rebus)
            config_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/rebus/chain.json
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

if [[ ${set_u} == "true" ]]; then
    set -u
else
    set +u
fi

chain_file=./chain.json

curl -sSfl "$config_url" > "$chain_file"

chain="$(jq -Mr '.chain_name' "$chain_file")"
echo "fetching chain info for $chain"

DAEMON_NAME="$(jq -Mr '.daemon_name' "$chain_file")"

ENV_PREFIX=${CONFIG_ENV_PREFIX:-"$(echo -n ${DAEMON_NAME}_ | tr '[:lower:]' '[:upper:]')"}
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

CHAIN_HOME=${CHAIN_HOME:-"$(jq -Mr '.node_home' "$chain_file")"}

# if default path is in use it will be in format $HOME/.<daemon_name> so env needs to be evaluated
CHAIN_HOME="$(echo "${CHAIN_HOME}" | envsubst)"
CHAIN_CHAIN_ID=$(jq -Mr '.chain_id' "$chain_file")

[[ -f /boot/prerun1.sh ]] && /boot/prerun1.sh

if [[ ! -f "$CHAIN_HOME/cosmovisor/genesis/bin/$DAEMON_NAME" ]]; then
    mkdir -p "$CHAIN_HOME/cosmovisor/genesis/bin"
fi

if [[ ! -e "$CHAIN_HOME/cosmovisor/current" ]]; then
    ln -snf "$CHAIN_HOME/cosmovisor/genesis" "$CHAIN_HOME/cosmovisor/current"
fi

if [ ! -f "$CHAIN_HOME/cosmovisor/current/bin/$DAEMON_NAME" ]; then
    if [[ ${download_binary} == "true" ]]; then
        git_repo=$(jq -Mr '.codebase.git_repo' "$chain_file")
        recommended_version=$(jq -Mr '.codebase.recommended_version' "$chain_file")

        echo "installing chain recommended version of \"$DAEMON_NAME\", version: $recommended_version"

        pushd $(pwd)
        mkdir src && cd src
        git config --global advice.detachedHead false
        git clone --branch $recommended_version --depth 1 $git_repo .

        if [[ -d /config/patches/$DAEMON_NAME/$recommended_version ]]; then
            for patch in /config/patches/$DAEMON_NAME/$recommended_version/* ; do
                git apply $patch
            done
        fi

        GOBIN=$(readlink -f "$CHAIN_HOME/cosmovisor/current/bin") make install
        unset GOBIN

        popd
        rm -rf src
    else
        echo "daemon file "$CHAIN_HOME/cosmovisor/genesis/bin/$DAEMON_NAME" cannot be found."
        echo "set CONFIG_DOWNLOAD_RECOMMENDED_BINARY, or download and install appropriate release into $CHAIN_HOME/cosmovisor/genesis/bin"
        exit 1
    fi
fi

if [ ! -f "$CHAIN_HOME/config/config.toml" ]; then
    echo "initializing chain home dir $CHAIN_HOME"

    blank_data

    # "or" condition after the head command is to filter out SIGPIPE error code
    CHAIN_MONIKER=${CHAIN_MONIKER:-$(cat /dev/urandom | tr -dc '[:alpha:]' | fold -w ${1:-20} | head -n 1 || (ec=$? ; if [ "$ec" -eq 141 ]; then exit 0; else exit "$ec"; fi))}
    $CHAIN_HOME/cosmovisor/current/bin/$DAEMON_NAME init $CHAIN_MONIKER --home "$CHAIN_HOME" --chain-id="$CHAIN_CHAIN_ID"
    import_genesis=true
elif [ ! -f "$CHAIN_HOME/config/genesis.json" ]; then
    import_genesis=true
fi

if [[ ${import_genesis} == "true" ]]; then
    echo "importing chain genesis into $CHAIN_HOME"
    genesis_url=$(cat "$chain_file" | jq -Mr '.genesis.genesis_url')
    genesis_url=$(curl -kIsL -w "%{url_effective}" -o /dev/null "$genesis_url")

    echo "genesis: $genesis_url"

    case "$genesis_url" in
    *.json)
        curl -sfl "$genesis_url" > "$CHAIN_HOME/config/genesis.json"
        ;;
    *.zip)
        curl -sL "$genesis_url" | bsdtar -xf - -C "$CHAIN_HOME/config/"
        ;;
    *.gz)
        curl -sL "$genesis_url" | gzip -d > "$CHAIN_HOME/config/genesis.json"
        ;;
    *.tar.gz)
        curl -sL "$genesis_url" | tar -xzf - -C "$CHAIN_HOME/config/"
        ;;
    *)
        echo "unsupported genesis un-archive file format: $genesis_url"
        usage
        ;;
    esac
fi

if [[ ${reset_data} == "true" ]]; then
    echo "cleaning data dir"
    rm -rf $CHAIN_HOME/data/*

    blank_data
fi

if ! env | grep -q "^CHAIN_P2P_SEEDS" ; then
    if ! cat "$chain_file" | jq -Mr '.peers.seeds[]' &> /dev/null ; then
        echo "chain file does not contain seeds"
    else
        if [[ $peer_validation == true ]]; then
            echo "validating seeds"
        else
            echo "skipping seeds validation"
        fi

        seeds=
        while read id ip port; do
            if [[ $peer_validation == true ]]; then
                echo "validating seed: ${id}@${ip}:${port}"
                if timeout 1s nc -vz $ip $port >/dev/null 2>&1 ; then
                    echo "    PASS"
                    [[ "$seeds" == "" ]] && seeds=${id}@${ip}:${port} || seeds="$seeds,${id}@${ip}:${port}"
                else
                    echo "    FAIL"
                fi
            else
                [[ "$seeds" == "" ]] && seeds=${id}@${ip}:${port} || seeds="$seeds,${id}@${ip}:${port}"
            fi
        done <<< $(cat "$chain_file" | jq -Mr '.peers.seeds[] | [.id, .address|gsub(":"; " ")] | @tsv')
        declare CHAIN_P2P_SEEDS="$seeds"
    fi
else
    echo "CHAIN_P2P_SEEDS is set explicitly. ignoring chain seeds"
fi

if ! env | grep -q "^CHAIN_P2P_PERSISTENT_PEERS" ; then
    if ! cat "$chain_file" | jq -Mr '.peers.persistent_peers[]' &> /dev/null ; then
        echo "chain file does not contain persistent peers"
    else
        if [[ $peer_validation == true ]]; then
            echo "validating peers"
        else
            echo "skipping peers validation"
        fi

        peers=
        while read id ip port; do
            if [[ $peer_validation == true ]]; then
                echo "validating persistent peer: ${id}@${ip}:${port}"
                if timeout 1s nc -vz $ip $port >/dev/null 2>&1 ; then
                    echo "    PASS"
                    [[ "$peers" == "" ]] && peers=${id}@${ip}:${port} || peers="$peers,${id}@${ip}:${port}"
                else
                    echo "    FAIL"
                fi
            else
                [[ "$peers" == "" ]] && peers=${id}@${ip}:${port} || peers="$peers,${id}@${ip}:${port}"
            fi
        done <<< $(cat "$chain_file" | jq -Mr '.peers.persistent_peers[] | [.id, .address|gsub(":"; " ")] | @tsv')
        declare CHAIN_P2P_PERSISTENT_PEERS="$peers"
    fi
else
    echo "CHAIN_P2P_PERSISTENT_PEERS is set explicitly. ignoring chain persistent peers"
fi

set +u
if [[ ! -z ${ADDITIONAL_P2P_SEEDS+x} ]]; then
    echo "applying additional seeds"
    if [[ "${CHAIN_P2P_SEEDS}" == "" ]]; then
        CHAIN_P2P_SEEDS=${ADDITIONAL_P2P_SEEDS}
    else
        CHAIN_P2P_SEEDS="${CHAIN_P2P_SEEDS},${ADDITIONAL_P2P_SEEDS}"
    fi
    declare CHAIN_P2P_SEEDS
fi

if [[ ! -z ${ADDITIONAL_P2P_PERSISTENT_PEERS+x} ]]; then
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

if [ ${CHAIN_STATESYNC_ENABLE} == true ]; then
    oIFS="$IFS"
    IFS=","
    declare -a rpc_array=($CHAIN_STATESYNC_RPC_SERVERS)
    IFS="$oIFS"
    unset oIFS

    [[ ${#rpc_array[@]} -eq 1 ]] && rpc_array+=($CHAIN_STATESYNC_RPC_SERVERS)

    unset CHAIN_STATESYNC_RPC_SERVERS

    height_diff=${BLOCK_HEIGHT_DIFF:-2000}

    LATEST_HEIGHT=$(curl -sL ${rpc_array[0]}/block | jq -r .result.block.header.height)
    BLOCK_HEIGHT=$((LATEST_HEIGHT - height_diff))
    TRUST_HASH=$(curl -sL "${rpc_array[0]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)

    CHAIN_STATESYNC_RPC_SERVERS=${rpc_array[0]}

    for (( i=1; i<${#rpc_array[@]}; i++ )); do
        test_hash=$(curl -sL "${rpc_array[i]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
        if [[ $TRUST_HASH != $test_hash ]]; then
            echo "TRUST hash for block $BLOCK_HEIGHT does not match
    ${rpc_array[0]} : $TRUST_HASH
    ${rpc_array[i]} : $test_hash
"
            exit 1
        fi

        CHAIN_STATESYNC_RPC_SERVERS="${CHAIN_STATESYNC_RPC_SERVERS},${rpc_array[i]}"
    done

    export CHAIN_STATESYNC_RPC_SERVERS
    export CHAIN_STATESYNC_TRUST_HEIGHT=${BLOCK_HEIGHT}
    export CHAIN_STATESYNC_TRUST_HASH=${TRUST_HASH}
fi

DAEMON_HOME=${CHAIN_HOME}

while IFS="=" read var val; do
    varname=$(echo $var | sed -e "s/^CHAIN_/$ENV_PREFIX/")
    unset $var
    declare ${varname}=$val
    export ${varname}
done <<< $(env | grep ^"CHAIN_")

export UNSAFE_SKIP_BACKUP
export DAEMON_NAME
export DAEMON_HOME

env | sort | grep -q "^CHAIN_" && echo "some env variable starting with CHAIN_ have not been unset" && exit 1

echo "dump current environment variables..."
env | sort | grep "^${ENV_PREFIX}\|^DAEMON_\|^CHAIN_"

[[ -f /boot/prerun2.sh ]] && /boot/prerun2.sh

exec cosmovisor run start |& grep -vi 'peer'
