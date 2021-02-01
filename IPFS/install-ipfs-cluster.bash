#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
LIST_OF_NODES="$1"
[[ -z "$LIST_OF_NODES" || ! "$LIST_OF_NODES" =~ @ ]] && echo "Must provide a comma separated list of node IPs as ARG1..." && exit 1
echo "== Be sure you're running this on your bootnode (the primary, or \"Golden\" node)!"
echo "== You can set the SSH_KEY ENV to the path of the private key you wish to use to SSH with"

# sleep 5
IPFS_CLUSTER_STORAGE_LOCATION="\$HOME/ipfs-cluster"
IPFS_PATH=".ipfs"
BIN_PATH="/usr/local/bin"
IPFS_CLUSTER_VERSION="v0.13.1"
[[ ! -z "$SSH_KEY" ]] && SSH_KEY="-i \"$SSH_KEY\""

ssh_and_run() {
  COMMANDS="$1"
  shift
  HOST="$1"
  COMMANDS="set -eo pipefail; $COMMANDS"
  [[ $HOST != localhost ]] && COMMANDS="$(command -v ssh) -o \"StrictHostKeyChecking=no\" $SSH_KEY $HOST \"export PATH=\\\"/usr/local/bin:\$PATH\\\";${COMMANDS//\$/\\\$}\""
  [[ $3 == silent ]] && echo && echo " = Executing $COMMANDS"
  eval "$COMMANDS"
}

rsync_to_node() {
  COMMAND="$(command -v rsync) -avzP -e 'ssh -o StrictHostKeyChecking=no $SSH_KEY' $1 $NODE:$2"
  echo " = Rsyncing: $COMMAND"
  eval "$COMMAND"
}

get-binary() {
  BINARY=$1
  TAR="${BINARY}_${IPFS_CLUSTER_VERSION}_darwin-amd64.tar.gz"
  eval curl -o "$IPFS_CLUSTER_STORAGE_LOCATION/$TAR" -O "https://dist.ipfs.io/$BINARY/$IPFS_CLUSTER_VERSION/$TAR"
  tar -xvzf "$TAR"
  eval mv $IPFS_CLUSTER_STORAGE_LOCATION/$BINARY/$BINARY $BIN_PATH/$BINARY
}

exit-cleanup() {
  cleanup localhost
  cleanup-nodes
}

cleanup() {
  ssh_and_run "
    ipfs shutdown || true
    pkill -9 ipfs || true
    rm -rf \$HOME/.ipfs* || true
  " $1
}

cleanup-nodes() {
  IFS=","
  for NODE in $LIST_OF_NODES; do
    cleanup $NODE
  done
  IFS=
}

prepare() {
  ssh_and_run "
    mkdir -p $IPFS_CLUSTER_STORAGE_LOCATION
  " $1
}

cluster-install() {
  ssh_and_run "
    $(declare -f get-binary)
    pushd $IPFS_CLUSTER_STORAGE_LOCATION &>/dev/null
    get-binary \"ipfs-cluster-ctl\"
    get-binary \"ipfs-cluster-service\"
    get-binary \"ipfs-cluster-follow\"
  " $1
}

init_ipfs() {
  # ipfs-cluster-service init --consensus crdt
  ssh_and_run "
    ipfs init
    ipfs bootstrap rm --all
  " $1
  [[ "$1" != "localhost" ]] && rsync_to_node ./.swarm.key "\\\$HOME/.ipfs/swarm.key" || cp -rfp ./.swarm.key "$HOME/.ipfs/swarm.key"
  true
}

run_daemons() {
  ssh_and_run "
    export LIBP2P_FORCE_PNET=1
    ipfs daemon &>/tmp/ipfs-daemon.log &
    sleep 5
    echo '================================='
    tail -10 /tmp/ipfs-daemon.log
  " $1
  # ssh_and_run "
  #   ipfs-cluster-service daemon &>/tmp/ipfs-cluster-daemon.log &
  # " $1
  true
}

cleanup localhost &>/dev/null
cleanup-nodes &>/dev/null

if [[ ! "$@" =~ --uninstall ]]; then
  echo "]] Preparing this machine as Bootnode"
  trap exit-cleanup 0
  prepare localhost
  # cluster-install localhost
  init_ipfs localhost
  FIRST_NODE_ID="$(ipfs id | grep "ID\"" | cut -d\" -f4)"
  FIRST_NODE_IP="$(ifconfig | grep 192 | awk '{print $2}' | xargs)"

  IFS=","
  for NODE in $LIST_OF_NODES; do
    echo "]] Preparing Node: $NODE"
    # echo "]]] Cleanup" && cleanup $NODE
    echo "]] Prepare" && prepare $NODE
    # cluster-install $NODE
    init_ipfs $NODE
    # Add first node ID/IP as peer to others
    ssh_and_run "
      ipfs bootstrap add /ip4/$FIRST_NODE_IP/tcp/4001/p2p/$FIRST_NODE_ID
    " $NODE
  done
  IFS=

  IFS=","
  for NODE in $LIST_OF_NODES; do
    NODE_IP="$(echo $NODE | cut -d@ -f2)"
    NODE_ID=$(ssh_and_run "ipfs id | grep \\\"ID\\\\\\\"\\\" | cut -d\\\\\\\" -f4" $NODE silent)
    ipfs bootstrap add /ip4/$NODE_IP/tcp/4001/p2p/$NODE_ID # Add the node as a bootstrapper to the machine running this script ("FIRST_NODE")
    for OTHER_NODE in $LIST_OF_NODES; do # Ensure each node is connected to the others
      [[ $OTHER_NODE == $NODE ]] && continue
      OTHER_NODE_IP="$(echo $OTHER_NODE | cut -d@ -f2)"
      OTHER_NODE_ID=$(ssh_and_run "ipfs id | grep \\\"ID\\\\\\\"\\\" | cut -d\\\\\\\" -f4" $OTHER_NODE silent)
      ssh_and_run "ipfs bootstrap add /ip4/$OTHER_NODE_IP/tcp/4001/p2p/$OTHER_NODE_ID" $NODE
    done
  done

  run_daemons localhost
  for NODE in $LIST_OF_NODES; do
    run_daemons $NODE
  done
  IFS=

  while true; do
    echo ""
    echo "Press any key to stop the server"
    read -p ''
    exit 0
  done

fi
exit 
