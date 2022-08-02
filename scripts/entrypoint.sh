#!/usr/bin/env bash

#set -x
set -e
set -o pipefail

function usage() {
echo "
supported values to the CHAIN env variable
    - akash
    - sifchain
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
    "")
        echo "CHAIN is not set"
        usage
        ;;
    *)
        echo "unsupported chain: $CHAIN"
        usage
        ;;
esac

set -u

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

echo "validating peers and seeds"

env | grep -q "^CHAIN_P2P_SEEDS" || declare CHAIN_P2P_SEEDS="$(cat "$chain_file" | jq -Mr '.peers.seeds[] | [.id, .address|gsub(":"; " ")] | @tsv' | while read id ip port; do timeout 2s nc -vz $ip $port >/dev/null 2>&1 && echo ${id}@${ip}:${port}; done | paste -sd, -)"
env | grep -q "^CHAIN_P2P_PERSISTENT_PEERS" || declare CHAIN_P2P_PERSISTENT_PEERS=$(cat "$chain_file" | jq -Mr '.peers.persistent_peers[] | [.id, .address|gsub(":"; " ")] | @tsv' | while read id ip port; do timeout 2s nc -vz $ip $port >/dev/null 2>&1 && echo ${id}@${ip}:${port}; done | paste -sd, -)

set +u
if [[ ! -z ${ADDITIONAL_P2P_SEEDS+x} ]]; then
    peers=${CHAIN_P2P_SEEDS}
    declare CHAIN_P2P_SEEDS=${ADDITIONAL_P2P_SEEDS}

    if [[ ${peers} != "" ]]; then
        declare CHAIN_P2P_SEEDS="${CHAIN_P2P_SEEDS},${peers}"
    fi
fi

if [[ ! -z ${ADDITIONAL_P2P_PERSISTENT_PEERS+x} ]]; then
    peers=${CHAIN_P2P_PERSISTENT_PEERS}
    declare CHAIN_P2P_PERSISTENT_PEERS=${ADDITIONAL_P2P_PERSISTENT_PEERS}

    if [[ ${peers} != "" ]]; then
        declare CHAIN_P2P_PERSISTENT_PEERS="${CHAIN_P2P_PERSISTENT_PEERS},${peers}"
    fi
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

    LATEST_HEIGHT=$(curl -s ${rpc_array[0]}/block | jq -r .result.block.header.height)
    BLOCK_HEIGHT=$((LATEST_HEIGHT - 2000))
    TRUST_HASH=$(curl -s "${rpc_array[0]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)

    CHAIN_STATESYNC_RPC_SERVERS=${rpc_array[0]}

    for (( i=1; i<${#rpc_array[@]}; i++ )); do
        test_hash=$(curl -s "${rpc_array[i]}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
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

export DAEMON_NAME
export DAEMON_HOME

env | sort | grep -q "^CHAIN_" && echo "some env variable starting with CHAIN_ has not been unset" && exit 1
env | sort | grep "^${ENV_PREFIX}\|^DAEMON_\|^CHAIN_"
exec cosmovisor run start |& grep -vi 'peer'
