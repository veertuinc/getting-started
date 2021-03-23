#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo "]] Cleaning up the previous Prometheus installation"
docker-compose down &>/dev/null || true
docker stop $PROMETHEUS_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $PROMETHEUS_DOCKER_CONTAINER_NAME &>/dev/null || true
[[ -d $PROMETHEUS_DOCKER_DATA_DIR ]] && sudo rm -rf $PROMETHEUS_DOCKER_DATA_DIR
rm -rf docker-compose.yml
if [[ $1 != "--uninstall" ]]; then
  modify_hosts $PROMETHEUS_DOCKER_CONTAINER_NAME
  echo "]] Starting the Prometheus Docker container"
cat > docker-compose.yml <<BLOCK
version: '3.7'
services:
  $PROMETHEUS_DOCKER_CONTAINER_NAME:
    container_name: $PROMETHEUS_DOCKER_CONTAINER_NAME
    image: prom/prometheus:v$PROMETHEUS_DOCKER_TAG_VERSION
    restart: always
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--web.enable-admin-api'
      - '--web.enable-lifecycle'
    ports:
      - "$PROMETHEUS_PORT:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
BLOCK
  docker-compose up -d
  # Check if it's still starting...
  while [[ ! "$(docker logs --tail 100 $PROMETHEUS_DOCKER_CONTAINER_NAME 2>&1)" =~ 'Server is ready to receive web requests' ]]; do 
    docker logs --tail 10 $PROMETHEUS_DOCKER_CONTAINER_NAME 2>&1
    echo "Container still starting..."
    sleep 20
  done
  echo "============================================================================"
  echo "Prometheus UI: ${URL_PROTOCOL}$PROMETHEUS_DOCKER_CONTAINER_NAME:$PROMETHEUS_PORT"
  echo "To delete all of the metrics, simply re-run this script"
fi