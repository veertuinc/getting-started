#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
STORAGE_LOCATION="$SCRIPT_DIR/ipfs-cluster"
# [[ -d $STORAGE_LOCATION ]] && pushd $STORAGE_LOCATION &>/dev/null && docker-compose down; popd
# Cleanup
rm -rf $STORAGE_LOCATION
rm -rf $HOME/.ipfs*
BIN_PATH="/usr/local/bin"
# rm -f $BIN_PATH/ipfs-cluster-*
if [[ $1 != "--uninstall" ]]; then
  # brew install ipfs
  # VERSION="v0.13.1"
  # Prepare
  mkdir -p $STORAGE_LOCATION
  pushd $STORAGE_LOCATION &>/dev/null
  # INSTALL
  # get-binary() {
  #   BINARY=$1
  #   TAR="${BINARY}_${VERSION}_darwin-amd64.tar.gz"
  #   curl -o $STORAGE_LOCATION/$TAR -O https://dist.ipfs.io/$BINARY/$VERSION/$TAR
  #   tar -xvzf $TAR
  #   mv $STORAGE_LOCATION/$BINARY/$BINARY $BIN_PATH/$BINARY
  # }
  # get-binary "ipfs-cluster-ctl"
  # get-binary "ipfs-cluster-service"
  # get-binary "ipfs-cluster-follow"
  # Init
  ipfs-cluster-service init --consensus crdt
  ipfs init --profile server
  LIBP2P_FORCE_PNET=1
  if [[ ! -e ~/swarm.key ]]; then # https://github.com/ipfs/go-ipfs/blob/master/docs/experimental-features.md#private-networks
    go get github.com/Kubuxu/go-ipfs-swarm-key-gen/ipfs-swarm-key-gen
    ~/go/bin/ipfs-swarm-key-gen > ~/swarm.key
    ln -s ~/swarm.key ~/.ipfs/swarm.key
  fi
  ipfs bootstrap rm --all
  # Run daemons
  ipfs daemon &>/tmp/ipfs-daemon.log &
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
