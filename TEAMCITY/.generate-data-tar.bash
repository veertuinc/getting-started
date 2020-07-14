#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash
rm -f ${TEAMCITY_DOCKER_CONTAINER_NAME}-data.tar.gz
docker-compose down
cd $HOME
tar -czvf anka.teamcity-data.tar.gz anka.teamcity-data
cd "$SCRIPT_DIR"
mv $HOME/anka.teamcity-data.tar.gz .