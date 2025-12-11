#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash
SERVICE_PORT="8111"
# Cleanup
echo "]] Cleaning up the previous TeamCity installation"
set -x
execute-docker-compose down &>/dev/null || true
docker stop $TEAMCITY_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $TEAMCITY_DOCKER_CONTAINER_NAME &>/dev/null || true
rm -rf $TEAMCITY_DOCKER_DATA_DIR
rm -f docker-compose.yml
rm -rf $HOME/$TEAMCITY_DOCKER_CONTAINER_NAME.tar.gz
set +x
# Install
if [[ $1 != "--uninstall" ]]; then
  echo "]] Starting the TeamCity Docker container"
  echo "]]] Downloading the TeamCity data"
  curl -o $HOME/$TEAMCITY_DOCKER_CONTAINER_NAME-data.zip https://downloads.veertu.com/anka/$TEAMCITY_DOCKER_CONTAINER_NAME-data.zip
  echo "]]] Extracting the TeamCity data"
  pushd $HOME
    unzip $TEAMCITY_DOCKER_DATA_DIR.zip
    rm -rf $HOME/$TEAMCITY_DOCKER_CONTAINER_NAME.zip
  popd
cat > docker-compose.yml <<BLOCK
version: '3.7'
services:
  $TEAMCITY_DOCKER_CONTAINER_NAME:
    container_name: $TEAMCITY_DOCKER_CONTAINER_NAME
    image: jetbrains/teamcity-server:$TEAMCITY_DOCKER_TAG_VERSION
    platform: linux/amd64
    restart: always
    ports:
      - "$TEAMCITY_PORT:$SERVICE_PORT"
    volumes:
      - ${TEAMCITY_DOCKER_DATA_DIR}/datadir:/data/teamcity_server/datadir
      - ${TEAMCITY_DOCKER_DATA_DIR}/teamcity-startup.properties:/opt/teamcity/conf/teamcity-startup.properties
      - ${TEAMCITY_DOCKER_DATA_DIR}/logs:/opt/teamcity/logs
    environment:
      TEAMCITY_SERVER_MEM_OPTS: "-Xmx2440m"
      TEAMCITY_SERVER_OPTS: "-Dteamcity.kotlinConfigsDsl.pluginsCompilationXmx=1024m -Dteamcity.development.mode=true -Dteamcity.development.shadowCopyClasses=true -Dteamcity.cloudDebug=true"
BLOCK
if [[ "$(uname)" == "Linux" ]]; then
cat >> docker-compose.yml <<BLOCK
    extra_hosts:
      - "host.docker.internal:host-gateway"
BLOCK
fi
  execute-docker-compose up -d
  # docker logs --tail 100 $DOCKER_CONTAINER_NAME
  modify_hosts $TEAMCITY_DOCKER_CONTAINER_NAME
  echo "============================================================================"
  echo "Teamcity UI: ${URL_PROTOCOL}$TEAMCITY_DOCKER_CONTAINER_NAME:$TEAMCITY_PORT
Logins: admin / admin
Documentation: https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/teamcity"
fi