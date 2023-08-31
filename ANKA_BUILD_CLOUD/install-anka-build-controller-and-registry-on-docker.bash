#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
# Warn about node being joined
if [[ "$(sudo ankacluster status)" =~ "status: running" ]]; then
  echo "You have this machine (node) joined to the Cloud! Please disjoin before uninstalling or reinstalling with: sudo ankacluster disjoin"
  exit 1
fi
if [[ "$(sudo anka-controller status)" =~ "is Running" ]]; then
  echo "The native cloud package is running already. Turn it off with: sudo anka-controller stop"
  exit 1
fi
echo "]] Cleaning up the previous Anka Cloud installation"
mkdir -p "${CLOUD_DOCKER_FOLDER}" && cd "${CLOUD_DOCKER_FOLDER}"
execute-docker-compose down &>/dev/null || true
docker stop "${CLOUD_CONTROLLER_ADDRESS}" &>/dev/null || true
docker rm "${CLOUD_CONTROLLER_ADDRESS}" &>/dev/null || true
docker stop "${CLOUD_REGISTRY_ADDRESS}" &>/dev/null || true
docker rm "${CLOUD_REGISTRY_ADDRESS}" &>/dev/null || true
docker stop "${CLOUD_ETCD_ADDRESS}" &>/dev/null || true
docker rm "${CLOUD_ETCD_ADDRESS}" &>/dev/null || true
# Install
if [[ $1 != "--uninstall" ]]; then
  mkdir -p "${HOME}/anka-docker-etcd-data"
  [[ "$(uname)" == "Linux" ]] && mkdir -p "${CLOUD_REGISTRY_STORAGE_LOCATION}" || sudo mkdir -p "${CLOUD_REGISTRY_STORAGE_LOCATION}"
  [[ -d "${CLOUD_REGISTRY_STORAGE_LOCATION}" ]] && sudo chmod -R 777 "${CLOUD_REGISTRY_STORAGE_LOCATION}" # Ensure that docker and the native package can use the same templates
  # Download
  if [[ -z $1 ]]; then
    echo "]] Downloading $CLOUD_DOCKER_TAR"
    curl -S -L -O "$CLOUDFRONT_URL/$CLOUD_DOCKER_TAR"
    INSTALLER_LOCATION="$(pwd)/$CLOUD_DOCKER_TAR"
  else
    [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your installer package" && exit 1
    INSTALLER_LOCATION="$1"
    echo "]] Installing $INSTALLER_LOCATION"
  fi
  tar -xzvf $CLOUD_DOCKER_TAR
  # Configuration
  echo "]] Modifying the docker-compose.yml"
CLOUD_ETCD_BUILD_BLOCK=$(cat <<'BLOCK'
    build:
      context: etcd
BLOCK
)
CLOUD_CONTROLLER_BUILD_BLOCK=$(cat <<'BLOCK'
    build:
       context: controller
BLOCK
)
CLOUD_REGISTRY_BUILD_BLOCK=$(cat <<'BLOCK'
    build:
      context: registry
BLOCK
)
if ${CLOUD_USE_DOCKERHUB:-false}; then
CLOUD_ETCD_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-etcd:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f5)
BLOCK
)
CLOUD_CONTROLLER_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-controller:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f5)
BLOCK
)
CLOUD_REGISTRY_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-registry:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f5)
BLOCK
)
fi
cat << BLOCK | sudo tee docker-compose.yml > /dev/null
version: '2'
services:
  anka-controller:
    container_name: anka.controller
${CLOUD_CONTROLLER_BUILD_BLOCK}
    ports:
       - "${CLOUD_CONTROLLER_PORT}:80"
    depends_on:
       - etcd
       - anka-registry
    environment:
      ANKA_ANKA_REGISTRY: "http://$CLOUD_REGISTRY_ADDRESS:8089"
      ANKA_ETCD_ENDPOINTS: "$CLOUD_ETCD_ADDRESS:2379"
      ANKA_ENABLE_CENTRAL_LOGGING: "true"
      ANKA_LISTEN_ADDR: :80
      ANKA_LOG_DIR: /var/log/anka-controller
      ANKA_LOCAL_ANKA_REGISTRY: http://anka-registry:8089
    restart: always

  anka-registry:
    container_name: anka.registry
${CLOUD_REGISTRY_BUILD_BLOCK}
    environment:
      ANKA_BASE_PATH: /mnt/vol
      ANKA_LISTEN_ADDR: :8089
    ports:
      - "8089:8089"
    restart: always
    volumes:
      - "${CLOUD_REGISTRY_STORAGE_LOCATION}:/mnt/vol"

  etcd:
    container_name: anka.etcd
${CLOUD_ETCD_BUILD_BLOCK}
    volumes:
      - ${HOME}/anka-docker-etcd-data:/etcd-data
    environment:
      ETCD_DATA_DIR: /etcd-data
      ETCD_LISTEN_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_ADVERTISE_CLIENT_URLS: http://0.0.0.0:2379
      ETCD_LISTEN_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_ADVERTISE_PEER_URLS: http://0.0.0.0:2380
      ETCD_INITIAL_CLUSTER: my-etcd=http://0.0.0.0:2380
      ETCD_INITIAL_CLUSTER_TOKEN: my-etcd-token
      ETCD_INITIAL_CLUSTER_STATE: new
      ETCD_AUTO_COMPACTION_RETENTION: 30m
      ETCD_AUTO_COMPACTION_MODE: periodic
      ETCD_NAME: my-etcd
    restart: always

BLOCK
if [[ "$(uname)" == "Linux" ]]; then
cat >> docker-compose.yml <<BLOCK
    extra_hosts:
      - "host.docker.internal:host-gateway"
BLOCK
fi
  echo "]] Starting the Anka Build Cloud Controller & Registry"
  execute-docker-compose up -d --build
  # Set Hosts
  [[ "${CLOUD_CONTROLLER_ADDRESS}" == "anka.controller" ]] && modify_hosts "${CLOUD_CONTROLLER_ADDRESS}" &>/dev/null
  [[ "${CLOUD_REGISTRY_ADDRESS}" == "anka.registry" ]] && modify_hosts "${CLOUD_REGISTRY_ADDRESS}" &>/dev/null
  modify_hosts "${CLOUD_ETCD_ADDRESS}" &>/dev/null
  # Ensure we have the right Anka Agent version installed (for rolling back versions)
  if [[ $(uname) == "Darwin" ]]; then
    echo "]] Joining this machine (Node) to the Cloud"
    sleep 40
    cd $STORAGE_LOCATION
    [[ "$(arch)" == "arm64" ]] && AGENT_PKG="AnkaAgentArm.pkg" || ANKA_PKG="AnkaAgent.pkg"
    sudo curl -O "${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}/pkg/${AGENT_PKG}" -o /tmp/ && sudo installer -pkg "/tmp/${AGENT_PKG}" -tgt /
    sudo ankacluster join "${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}" --host $DOCKER_HOST_ADDRESS --groups "gitlab-test-group-env" || true
  fi
  #
  echo "============================================================================="
  echo "Controller UI:  ${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}"
  echo "Registry:       ${URL_PROTOCOL}${CLOUD_REGISTRY_ADDRESS}:${CLOUD_REGISTRY_PORT}"
  echo "Documentation:  https://docs.veertu.com/anka/anka-build-cloud/"
  if [[ ! -z $EXTRA_NOTE ]]; then
    echo "$EXTRA_NOTE
    "
  fi
fi