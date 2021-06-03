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
  [[ -d "/Library/Application Support/Veertu/Anka/registry" ]] && sudo chmod -R 777 "/Library/Application Support/Veertu/Anka/registry" # Ensure that docker and the native package can use the same templates
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
      context: .
      dockerfile: etcd.docker
BLOCK
)
CLOUD_CONTROLLER_BUILD_BLOCK=$(cat <<'BLOCK'
    build:
       context: .
       dockerfile: anka-controller.docker
BLOCK
)
CLOUD_REGISTRY_BUILD_BLOCK=$(cat <<'BLOCK'
    build:
        context: .
        dockerfile: anka-registry.docker
BLOCK
)
if ${CLOUD_USE_DOCKERHUB:-false}; then
CLOUD_ETCD_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-etcd:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f4)
BLOCK
)
CLOUD_CONTROLLER_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-controller:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f4)
BLOCK
)
CLOUD_REGISTRY_BUILD_BLOCK=$(cat <<BLOCK
    image: veertu/anka-build-cloud-registry:v$(echo $CLOUD_DOCKER_TAR | cut -d- -f4)
BLOCK
)
mkdir -p "${HOME}/anka-docker-etcd-data"
sudo mkdir -p "/Library/Application Support/Veertu/Anka/registry"
fi
cat << BLOCK | sudo tee docker-compose.yml > /dev/null
version: '2'
services:
  anka-etcd:
    container_name: anka.etcd
${CLOUD_ETCD_BUILD_BLOCK}
    ports:
      - "2379:2379"
    volumes:
      - ${HOME}/anka-docker-etcd-data:/etcd-data
    restart: always
    command: /usr/bin/etcd --data-dir /etcd-data --listen-client-urls http://0.0.0.0:2379  --advertise-client-urls http://0.0.0.0:2379  --listen-peer-urls http://0.0.0.0:2380 --initial-advertise-peer-urls http://0.0.0.0:2380  --initial-cluster my-etcd=http://0.0.0.0:2380 --initial-cluster-token my-etcd-token --initial-cluster-state new --auto-compaction-retention 1 --name my-etcd

  anka-controller:
    container_name: anka.controller
${CLOUD_CONTROLLER_BUILD_BLOCK}
    ports:
       - "${CLOUD_CONTROLLER_PORT}:80"
    depends_on:
       - anka-etcd
       - anka-registry
    restart: always
    entrypoint: ["/bin/bash", "-c", "anka-controller --enable-central-logging --anka-registry http://$CLOUD_REGISTRY_ADDRESS:8089 --etcd-endpoints $CLOUD_ETCD_ADDRESS:2379 --log_dir /var/log/anka-controller --local-anka-registry http://anka-registry:8085"]

  anka-registry:
    container_name: anka.registry
${CLOUD_REGISTRY_BUILD_BLOCK}
    ports:
        - "8089:8089"
    restart: always
    volumes:
      - "/Library/Application Support/Veertu/Anka/registry:/mnt/vol"
BLOCK
  echo "]] Starting the Anka Build Cloud Controller & Registry"
  execute-docker-compose up -d
  # Set Hosts
  [[ "${CLOUD_CONTROLLER_ADDRESS}" == "anka.controller" ]] && modify_hosts "${CLOUD_CONTROLLER_ADDRESS}" &>/dev/null
  [[ "${CLOUD_REGISTRY_ADDRESS}" == "anka.registry" ]] && modify_hosts "${CLOUD_REGISTRY_ADDRESS}" &>/dev/null
  modify_hosts "${CLOUD_ETCD_ADDRESS}" &>/dev/null
  # Ensure we have the right Anka Agent version installed (for rolling back versions)
  if [[ $(uname) == "Darwin" ]]; then
    echo "]] Joining this machine (Node) to the Cloud"
    sleep 20
    cd $STORAGE_LOCATION
    sudo curl -O "${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}/pkg/AnkaAgent.pkg" -o /tmp/ && sudo installer -pkg /tmp/AnkaAgent.pkg -tgt /
    sudo ankacluster join "${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}" --host 172.17.0.1 || true
  fi
  #
  echo "============================================================================="
  echo "Controller UI:  ${URL_PROTOCOL}${CLOUD_CONTROLLER_ADDRESS}:${CLOUD_CONTROLLER_PORT}"
  echo "Registry:       ${URL_PROTOCOL}${CLOUD_REGISTRY_ADDRESS}:${CLOUD_REGISTRY_PORT}"
  echo "Documentation:  https://ankadocs.veertu.com/docs/getting-started/linux/"
  if [[ ! -z $EXTRA_NOTE ]]; then
    echo "$EXTRA_NOTE
    "
  fi
fi