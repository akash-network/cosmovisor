#!/usr/bin/env bash

set_x=${SHELL_SET_X:-false}
set_e=${SHELL_SET_E:-true}
set_u=${SHELL_SET_U:-true}

chain_import_genesis=${CHAIN_IMPORT_GENESIS:-false}
unset CHAIN_IMPORT_GENESIS

set_pipefail=${SHELL_SET_PIPEFAIL:-true}

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

err_report() {
    echo "Error occurred:"
    awk 'NR>L-4 && NR<L+4 { printf "%-5d%3s%s\n",NR,(NR==L?">>>":""),$0 }' L=$1 $0
}

trap 'err $LINENO' ERR

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

case "${CHAIN}" in
    akash)
        chain_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/akash/chain.json
        ;;
    sifchain)
        chain_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/sifchain/chain.json
        ;;
    stride)
        chain_url=https://raw.githubusercontent.com/cosmos/chain-registry/master/stride/chain.json
        ;;
    rebus)
        chain_url=https://raw.githubusercontent.com/rebuschain/chain-registry/feature/add-rebus-coin/rebus/chain.json
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

if [[ ${set_u} == "true" ]]; then
    set -u
else
    set +u
fi

chain_file=./chain.json

curl -sSfl "$chain_url" > "$chain_file"

echo "fetching chain info for $CHAIN"

unset CHAIN

DAEMON_NAME="$(jq -Mr '.daemon_name' "$chain_file")"
ENV_PREFIX="$(echo -n ${DAEMON_NAME}_ | tr '[:lower:]' '[:upper:]')"

function echo_dname() {
    varname=$1
    echo "$1"
}

function echo_dval() {
    echo "${!1}"
}

CHAIN_HOME=${CHAIN_HOME:-"$(jq -Mr '.node_home' "$chain_file")"}

# if default path is in use it will be in format $HOME/.<daemon_name> so env needs to be evaluated
export CHAIN_HOME="$(echo "${CHAIN_HOME}" | envsubst)"
export CHAIN_CHAIN_ID=$(jq -Mr '.chain_id' "$chain_file")

if [[ ${chain_import_genesis} == "true" ]]; then
    echo "importing chain genesis into $CHAIN_HOME"
    genesis_url=$(cat "$chain_file" | jq -Mr '.genesis.genesis_url')
    curl -L "$genesis_url" | bsdtar -xvf - -C "$CHAIN_HOME/"
fi

if ! env | grep -q "^CHAIN_P2P_SEEDS" ; then
    if ! cat "$chain_file" | jq -Mr '.peers.seeds[]' &> /dev/null ; then
        echo "chain file does not contain seeds"
    else
        echo "validating seeds"

        seeds=
        while read id ip port; do
            echo "validating seed: ${id}@${ip}:${port}"
            if timeout 2s nc -vz $ip $port >/dev/null 2>&1 ; then
                echo "    PASS"
                [[ "$seeds" == "" ]] && seeds=${id}@${ip}:${port} || seeds="$seeds,${id}@${ip}:${port}"
            else
                echo "    FAIL"
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
        echo "validating peers"

        peers=
        while read id ip port; do
            echo "validating persistent peer: ${id}@${ip}:${port}"
            if timeout 2s nc -vz $ip $port >/dev/null 2>&1 ; then
                echo "    PASS"
                [[ "$peers" == "" ]] && peers=${id}@${ip}:${port} || peers="$peers,${id}@${ip}:${port}"
            else
                echo "    FAIL"
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

# enable statesync by default
export CHAIN_STATESYNC_ENABLE=${CHAIN_STATESYNC_ENABLE:-true}

if [ ${CHAIN_STATESYNC_ENABLE} == true ]; then
    set +u
    if [ -z "${CHAIN_STATESYNC_RPC_SERVERS}" ]; then
        echo "CHAIN_STATESYNC_RPC_SERVERS is not set"
        exit 1
    fi
    set -u

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
    varname=$ENV_PREFIX$(echo $var | sed -e "s/^CHAIN_//")
    unset $var
    declare ${varname}=$val
    export ${varname}
done <<< $(env | grep ^"CHAIN_")

if [[ ! -z ${ADDITIONAL_P2P_PERSISTENT_PEERS+x} ]]; then
    peers=${CHAIN_P2P_PERSISTENT_PEERS}
    declare CHAIN_P2P_PERSISTENT_PEERS=${ADDITIONAL_P2P_PERSISTENT_PEERS}

    if [[ ${peers} != "" ]]; then
        declare CHAIN_P2P_PERSISTENT_PEERS="${CHAIN_P2P_PERSISTENT_PEERS},${peers}"
    fi
fi

set +u
if [[ ! -z ${DAEMON_UNSAFE_SKIP_BACKUP} ]]; then
    declare UNSAFE_SKIP_BACKUP=${DAEMON_UNSAFE_SKIP_BACKUP}
    unset $DAEMON_UNSAFE_SKIP_BACKUP
fi
set -u

export UNSAFE_SKIP_BACKUP
export DAEMON_NAME
export DAEMON_HOME

env | sort | grep -q "^CHAIN_" && echo "some env variable starting with CHAIN_ has not been unset" && exit 1
env | sort | grep "^${ENV_PREFIX}\|^DAEMON_\|^CHAIN_"

[[ -f /boot/prerun.sh ]] && /boot/prerun.sh

# exec cosmovisor run start |& grep -vi 'peer'
