#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
LIST_OF_NODES="$1"
[[ -z "$LIST_OF_NODES" ]] && echo "Must provide a comma separated list of node IPs as ARG1..." && exit 1
echo "== Be sure you're running this on your bootnode (the primary, or \"Golden\" node)!"
echo "== You can set the SSH_KEY ENV to the path of the private key you wish to use to SSH with"

# sleep 5
IPFS_CLUSTER_STORAGE_LOCATION="\\\$HOME/ipfs-cluster"
IPFS_PATH=".ipfs"
BIN_PATH="/usr/local/bin"
IPFS_CLUSTER_VERSION="v0.13.1"
[[ ! -z "$SSH_KEY" ]] && SSH_KEY="-i \"$SSH_KEY\""

ssh_and_run() {
  COMMAND="$(command -v ssh) -o \"StrictHostKeyChecking=no\" $SSH_KEY $NODE \"set -eo pipefail; set -x; $@\""
  echo " = Executing $COMMAND"
  eval "$COMMAND"
}

rsync_to_node() {
  COMMAND="$(command -v rsync) -avzP -e 'ssh -o StrictHostKeyChecking=no $SSH_KEY' $1 $NODE:$2"
  echo " = Rsyncing: $COMMAND"
  eval "$COMMAND"
}

get-binary() {
  BINARY=$1
  TAR="${BINARY}_${IPFS_CLUSTER_VERSION}_darwin-amd64.tar.gz"
  curl -o $IPFS_CLUSTER_STORAGE_LOCATION/$TAR -O https://dist.ipfs.io/$BINARY/$IPFS_CLUSTER_VERSION/$TAR
  tar -xvzf $TAR
  mv $IPFS_CLUSTER_STORAGE_LOCATION/$BINARY/$BINARY $BIN_PATH/$BINARY
}

cleanup() {
    ssh_and_run "
      ipfs shutdown || true
      pkill -9 ipfs || true
      rm -rf \\\$HOME/.ipfs* || true
    "
}

prepare() {
  ssh_and_run "
    mkdir -p $IPFS_CLUSTER_STORAGE_LOCATION
  "
}

install() {
  ssh_and_run "
    $(declare -f get-binary)
    pushd $IPFS_CLUSTER_STORAGE_LOCATION &>/dev/null
    get-binary \"ipfs-cluster-ctl\"
    get-binary \"ipfs-cluster-service\"
    get-binary \"ipfs-cluster-follow\"
  "
}

init_ipfs() {
  ssh_and_run "
    ipfs-cluster-service init --consensus crdt
    ipfs init --profile local-discovery
    LIBP2P_FORCE_PNET=1
    ipfs bootstrap rm --all
  "
  rsync_to_node ./.swarm.key ~/.ipfs/
}

run_daemons() {
  ssh_and_run "
    ipfs daemon &>/tmp/ipfs-daemon.log &
    IPFS_PEERID=$(ipfs config show | grep "PeerID")
    ipfs bootstrap add /ip4/192.168.0.135/tcp/4001/ipfs/
    sleep 10
    ipfs-cluster-service daemon &>/tmp/ipfs-cluster-daemon.log &
  "
}

echo "]] Preparing this machine as Bootnode"
echo "]]] Cleanup" && cleanup
if [[ ! "$@" =~ --uninstall ]]; then
  prepare
  install
  init_ipfs

IFS=","
for NODE in $LIST_OF_NODES; do
    echo "]] Preparing Node: $NODE"
    echo "]]] Cleanup" && cleanup
    if [[ ! "$@" =~ --uninstall ]]; then
      echo "]] Prepare" && prepare
      install
      init_ipfs

    fi
done
IFS=

exit 
# rm -f $BIN_PATH/ipfs-cluster-*
if [[ $1 != "--uninstall" ]]; then
  
  # Init
  ipfs-cluster-service init --consensus crdt
  ipfs init --profile local-discovery
  LIBP2P_FORCE_PNET=1
  if [[ ! -e $IPFS_PATH/swarm.key ]]; then # https://github.com/ipfs/go-ipfs/blob/master/docs/experimental-features.md#private-networks
    go get github.com/Kubuxu/go-ipfs-swarm-key-gen/ipfs-swarm-key-gen
    ~/go/bin/ipfs-swarm-key-gen > $IPFS_PATH
  fi
  ipfs bootstrap rm --all
  # Run daemons
  ipfs daemon &>/tmp/ipfs-daemon.log &
  IPFS_PEERID=$(ipfs config show | grep "PeerID")
  ipfs bootstrap add /ip4/192.168.0.135/tcp/4001/ipfs/$IPFS_PATH
  sleep 10
  ipfs-cluster-service daemon &>/tmp/ipfs-cluster-daemon.log &
    while true; do
      echo ""
      echo "Press any key to stop the server"
      read -p '' blah
      ipfs shutdown
      pkill -9 ipfs
      exit 0
    done
fi