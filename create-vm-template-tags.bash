#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with brew install jq." && exit 1
TEMPLATE=$1
[[ -z $TEMPLATE ]] && echo "No Template Name specified as ARG1..." && exit 1
HELPERS="set -exo pipefail;"
CERTS=""
[[ -f "$HOME/anka-node-$(hostname)-crt.pem" ]] && CERTS="--cacert /Users/nathanpierce/macmini-vault-registry/ca-root-crt.pem --cert /Users/nathanpierce/macmini-vault-registry/client-crt.pem --key /Users/nathanpierce/macmini-vault-registry/client-key.pem"
ANKA_RUN="sudo anka run -N -n"
ANKA_REGISTRY="sudo anka registry --remote $CLOUD_REGISTRY_REPO_NAME $CERTS"

pull() {
  [[ ! -z $1 ]] && TAG=$1
  $ANKA_REGISTRY pull $TEMPLATE -t $TAG
}

suspend_and_push() {
  echo "]] Suspending VM and pushing $TAG..."
  sudo anka suspend $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

stop_and_push() {
  sudo anka stop $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

does_not_exists() {
  [[ -z $(sudo anka --machine-readable registry --remote $CLOUD_REGISTRY_REPO_NAME $CERTS describe $TEMPLATE | jq -r ".body.versions[] | select(.tag == \"$TAG\") | .tag" 2>/dev/null) ]] && true || false
}

build-tag() {
  pull $3
  TAG="$1"
  echo "]] Building VM tag: $TAG..."
  if does_not_exists; then
    eval "$2"
    suspend_and_push
  fi
}

#############################
# Generate and push base tags
# Tripple quote nested quotes and $
####################################

TAG=${TAG:-"base"}
if does_not_exists; then
  suspend_and_push
fi
# Set port-forwarding
build-tag "$TAG:port-forward-22" "
  sudo anka modify $TEMPLATE add port-forwarding --guest-port 22 ssh || true
"
# Install Brew & command line tools (git)
build-tag "$TAG:brew-git" "
  $ANKA_RUN $TEMPLATE bash -c \"/bin/bash -c \\\"\\\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)\\\"\"
  $ANKA_RUN $TEMPLATE bash -c \"brew install jq\"
"

LEVEL_ONE_TAG=$TAG

if [[ $2 == '--gitlab' ]]; then
  build-tag "$LEVEL_ONE_TAG:gitlab" "
    $ANKA_RUN $TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 anka.gitlab' >> /etc/hosts && [[ ! -z \\\$(grep anka.gitlab /etc/hosts) ]]\"
  "
fi

if [[ $2 == '--jenkins' ]] || [[ $2 == '--teamcity' ]]; then
  ## Install OpenJDK8
  build-tag "$LEVEL_ONE_TAG:openjdk-1.8.0_242" "
    $ANKA_RUN $TEMPLATE bash -c \"$HELPERS cd /tmp && rm -f /tmp/OpenJDK* && \
    curl -L -O https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u242-b08/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg && \
    [ \\\$(du -s /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg | awk '{print \\\$1}') -gt 190000 ] && \
    sudo installer -pkg /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg -target / && \
    [[ ! -z \\\$(java -version 2>&1 | grep 1.8.0_242) ]] && \
    rm -f /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg\"
  " $LEVEL_ONE_TAG

  OPENJDK_TAGS="$TAG"
fi

if [[ $2 == '--jenkins' ]]; then
  ## Jenkins misc (Only needed if you're running Jenkins on the same host you run the VMs)
  build-tag "$OPENJDK_TAGS:jenkins" "
    $ANKA_RUN $TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 anka.jenkins' >> /etc/hosts && [[ ! -z \\\$(grep anka.jenkins /etc/hosts) ]]\"
  " $OPENJDK_TAGS
fi

if [[ $2 == '--teamcity' ]]; then
  build-tag "$OPENJDK_TAGS:teamcity" "
    $ANKA_RUN $TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 $TEAMCITY_DOCKER_CONTAINER_NAME' >> /etc/hosts && [[ ! -z \\\$(grep $TEAMCITY_DOCKER_CONTAINER_NAME /etc/hosts) ]]\"
    $ANKA_RUN $TEMPLATE bash -c \"curl -O -L https://download.jetbrains.com/teamcity/TeamCity-$TEAMCITY_VERSION.tar.gz\"
    $ANKA_RUN $TEMPLATE bash -c \"tar -xzvf TeamCity-$TEAMCITY_VERSION.tar.gz && mv Teamcity/BuildAgent /Users/anka/buildAgent\"
    $ANKA_RUN $TEMPLATE bash -c \"echo >> buildAgent/conf/buildagent.properties\"
    $ANKA_RUN $TEMPLATE bash -c \"sh buildAgent/bin/mac.launchd.sh load && sleep 5\"
  " $OPENJDK_TAGS
fi