# [Cosmovisor](https://github.com/cosmos/cosmos-sdk/tree/main/cosmovisor) in the Docker

The main purpose of this project is to simplify running different cosmos-sdk based chains using same docker container.
It combines into one image following things:
- [cosmovisor](https://github.com/cosmos/cosmos-sdk/tree/main/cosmovisor)
- [chain-registry](https://github.com/cosmos/chain-registry)
- download and build recommended binary version
- download genesis

## Capabilities
### Docker image `ghcr.io/akash-network/cosmovisor`
Supports following host/arch
- linux/amd64
- linux/arm64

Image version corresponds to the version of the [cosmovisor](https://github.com/cosmos/cosmos-sdk/tree/main/cosmovisor)

## Tested mainnet chains
- Akash
- Rebus
- Stride

## Configuration
### Chain environment variables
All environment variables related to the cosmos-sdk chain are starting with `CHAIN_` prefix.
Script will rewrite prefix to appropriate by each chain. For example, if chain is `akash` then `CHAIN_HOME` variable will be rewritten as `AKASH_HOME`

#### Special behavior of certain environment variables
 - `CHAIN_P2P_SEEDS` and `CHAIN_P2P_PERSISTENT_PEERS` - either set explicitly or extracted from `chain.json`
 - `ADDITIONAL_P2P_SEEDS` and `ADDITIONAL_P2P_PERSISTENT_PEERS` - useful when need to use peers from `chain.json` along with own list

### Config environment variables
 - `CONFIG_URL` - link to custom `chain.json` (testnet for example)
 - `CONFIG_FORCE_IMPORT_GENESIS` - (default false) download genesis file from link provided in `chain.json`
 - `CONFIG_RESET_DATA` - (default false) clean data dir in `--home=$CHAIN_HOME`
 - `CONFIG_DOWNLOAD_RECOMMENDED_BINARY` - (default false) download and install recommended binary into `$CHAIN_HOME/current/genesis/bin`
 - `CONFIG_ENV_PREFIX` - (default value based on the daemon name) custom env prefix instead of one
 - `CONFIG_PEER_VALIDATION` - (default true) perform connectivity check using `netcat`

### Daemon environment variable
All cosmovisor except `DAEMON_HOME` and `DAEMON_NAME` variables are available.
 - `DAEMON_HOME` - detected from chain info and set by script
 - `DAEMON_NAME` - detected from chain info and set by script
 - `DAEMON_ALLOW_DOWNLOAD_BINARIES` (optional), if set to true, will enable auto-downloading of new binaries (for security reasons, this is intended for full nodes rather than validators). By default, cosmovisor will not auto-download new binaries.
 - `DAEMON_RESTART_AFTER_UPGRADE` (optional, default = true), if true, restarts the subprocess with the same command-line arguments and flags (but with the new binary) after a successful upgrade. Otherwise (false), cosmovisor stops running after an upgrade and requires the system administrator to manually restart it. Note restart is only after the upgrade and does not auto-restart the subprocess after an error occurs.
 - `DAEMON_RESTART_DELAY` (optional, default none), allow a node operator to define a delay between the node halt (for upgrade) and backup by the specified time. The value must be a duration (e.g. 1s).
 - `DAEMON_POLL_INTERVAL` (optional, default 300 milliseconds), is the interval length for polling the upgrade plan file. The value must be a duration (e.g. 1s).
 - `DAEMON_DATA_BACKUP_DIR` option to set a custom backup directory. If not set, DAEMON_HOME is used.
 - `DAEMON_PREUPGRADE_MAX_RETRIES` (defaults to 0). The maximum number of times to call pre-upgrade in the application after exit status of 31. After the maximum number of retries, cosmovisor fails the upgrade.
 - `UNSAFE_SKIP_BACKUP` (defaults to false), if set to true, upgrades directly without performing a backup. Otherwise (false, default) backs up the data before trying the upgrade. The default value of false is useful and recommended in case of failures and when a backup needed to rollback. We recommend using the default backup option UNSAFE_SKIP_BACKUP=false.

### Prerun
Some configurations may want to execute custom code prior starting `cosmovisor`, download initial binary for example.
There is one prerun stages available and either of them or both can be used/omitted. 
Scripts must be named `prerun1.sh` and `prerun2.sh`
 - `prerun1.sh` - executed if found when chain file is downloaded, chain home and chain-id detected
 - `prerun2.sh` - executed if found right prior starting cosmovisor

### Debug shell behavior environment variables
 - `SHELL_SET_X` - (default false) dump shell execution
 - `SHELL_SET_E` - (default true) fail script on non-zero return codes
 - `SHELL_SET_U` - (default true) fail script if unbound variable is referenced

### Custom chain URL
Private testnets can also use this repo as long as they define appropriate `chain.json` and set it as

## Examples
Take a look [examples](examples) dir for docker compose runs.

### Akash
Starts two instances of akash - rpc (sentry) and validator behind it

#### Configuration
[.env](examples/akash/.env) contains common environment variables for both validator and akash
Enables statesync and downloads snapshot from polkachu servers.

##### Validator
Wipes content of `$CHAIN_HOME/data` on each restart

#### Run
```shell
cd examples/akash
docker compose up
```
