#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash
DATA_DIR_NAME="${TEAMCITY_DOCKER_CONTAINER_NAME}-data"
DATA_ZIP_NAME="${DATA_DIR_NAME}.zip"
rm -f "${DATA_ZIP_NAME}"
execute-docker-compose down
echo "teamcity.installation.completed=true" > "${HOME}/${DATA_DIR_NAME}/teamcity-startup.properties"
pushd "${HOME}"
  # -9 is max deflate compression; exclude runtime logs (keep config/_logging)
  zip -9 -r "${DATA_ZIP_NAME}" "${DATA_DIR_NAME}" \
    -x "${DATA_DIR_NAME}/logs/*" \
    -x "*.log" \
    -x "*/.teamcity/logs/*"
popd
mv "${HOME}/${DATA_ZIP_NAME}" .
aws s3 cp "${DATA_ZIP_NAME}" "s3://veertu-downloads/anka/${DATA_ZIP_NAME}" \
  --profile veertu \
  --region us-west-2
execute-docker-compose up -d