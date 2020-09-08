#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../../shared.bash
[[ -z $(sysctl -a | grep VMX) ]] && echo "Virtualization is not supported on your macOS... Needed for minikube..." && exit 1
if [[ $1 == '--uninstall' ]]; then
  minikube stop
  brew remove minikube
  exit
fi
# brew cask install –force virtualbox ## Virutalbox has some incompatibility with PVs: https://github.com/etcd-io/etcd/issues/5923
[[ -z $(command -v minikube) ]] && brew install minikube
minikube start --driver=docker \
  --memory $(($(sysctl -in hw.memsize) / 1024 / 1024 / 2)) \
  --cpus $(($(grep -c ^processor /proc/cpuinfo 2>/dev/null || sysctl -n hw.ncpu) / 2))
  # --nodes=3
minikube status