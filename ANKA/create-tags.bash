#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ../shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with brew install jq." && exit 1
TEMPLATE=$1
[[ -z $TEMPLATE ]] && echo "No Template Name specified as ARG1..." && exit 1
HELPERS="set -exo pipefail;"
CERTS=""
[[ -f "$HOME/anka-node-$(hostname)-crt.pem" ]] && CERTS="--cacert $HOME/anka-ca-crt.pem -c $HOME/anka-node-$(hostname)-crt.pem -k $HOME/anka-node-$(hostname)-key.pem"
ANKA_RUN="sudo anka run -N -n"
ANKA_REGISTRY="sudo anka registry --remote $CLOUD_REGISTRY_REPO_NAME $CERTS"

pull() {
  [[ ! -z $1 ]] && TAG=$1
  $ANKA_REGISTRY pull $TEMPLATE -t $TAG
}

suspend_and_push() {
  echo "Suspending VM and pushing $TAG..."
  sudo anka suspend $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

stop_and_push() {
  sudo anka stop $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

does_not_exists() {
  [[ -z $(sudo anka --machine-readable registry --remote $CLOUD_REGISTRY_REPO_NAME $CERTS describe $TEMPLATE | jq -r ".body.versions[] | select(.tag == \"$TAG\") | .tag") ]] && true || false
}

build-tag() {
  pull
  TAG="$1"
  echo "Building VM tag: $TAG..."
  if does_not_exists; then
    eval "$2"
    suspend_and_push
  fi
}

#############################
# Generate and push base tags
TAG=${TAG:-"base"}
if does_not_exists; then
  suspend_and_push
fi
# Set port-forwarding
build-tag "$TAG:port-forward-22" "
  sudo anka modify $TEMPLATE add port-forwarding --guest-port 22 ssh || true
"
# Install Brew & command line tools (git)
## Tripple quote nested quotes and $
build-tag "$TAG:brew-git" "
  $ANKA_RUN $TEMPLATE bash -c \"/bin/bash -c \\\"\\\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)\\\"\"
  $ANKA_RUN $TEMPLATE bash -c \"brew install jq\"
"