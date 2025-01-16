#!/bin/bash
set -exo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash
rm -f ${TEAMCITY_DOCKER_CONTAINER_NAME}-data.zip
execute-docker-compose down
echo "teamcity.installation.completed=true" > ~/anka.teamcity-data/teamcity-startup.properties
pushd "${HOME}"
    zip -9 -r anka.teamcity-data.zip anka.teamcity-data
popd
mv ~/anka.teamcity-data.zip .
execute-docker-compose up -d