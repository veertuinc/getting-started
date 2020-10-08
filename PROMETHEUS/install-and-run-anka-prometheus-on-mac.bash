#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo "]] Removing previous files and processes"
rm -f /tmp/$PROMETHEUS_BINARY_NAME
kill -15 $(pgrep "[a]nka-prometheus") 2>/dev/null || true
if [[ $1 != "--uninstall" ]]; then
  echo "]] Downloading $PROMETHEUS_BINARY_NAME from github"
  curl -L -O https://github.com/veertuinc/anka-prometheus/releases/download/v${PROMETHEUS_BINARY_VERSION}/${PROMETHEUS_BINARY_NAME}_v${PROMETHEUS_BINARY_VERSION}_darwin_amd64.zip
  chmod +x /tmp/$PROMETHEUS_BINARY_NAME
  echo "]] Running /tmp/$PROMETHEUS_BINARY_NAME --controller_address ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:${CLOUD_CONTROLLER_PORT} and backgrounding the process"
  /tmp/$PROMETHEUS_BINARY_NAME --controller_address ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:${CLOUD_CONTROLLER_PORT} &
  echo "================================================================"
  echo "PID: $(pgrep "[a]nka-prometheus")"
  echo "Endpoint URL: ${PROMETHEUS_DOCKER_CONTAINER_NAME}:2112"
fi