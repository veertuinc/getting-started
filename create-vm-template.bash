#!/bin/bash
set -eo pipefail
echo "]] Starting Anka VM Creation"
[[ "$(arch)" == "arm64" ]] && echo "Anka 3.0 (ARM) is currently not supported" && exit 1
MACOS_VERSION=${MACOS_VERSION:-"${1}"}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with: brew install jq" && exit 1
. ./.misc/get-macos-with-mist.bash
TEMPLATE_NAME="${MACOS_VERSION}"
INSTALLER_LOCATION="${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${MACOS_VERSION}${EXTENSION}"
if [[ "$1" != "--no-anka-create" ]]; then
  cd $HOME
  # Cleanup already existing Template
  sudo anka delete --yes $TEMPLATE_NAME &>/dev/null || true
  # Create Base Template
  echo "]] Creating $TEMPLATE_NAME using $INSTALLER_LOCATION (please be patient, it can take a while) ..."
  # Retry after an hour and a half just in case macos fails to install for some reason
  RETRIES=2
  NEXT_WAIT_TIME=0
  until [ ${NEXT_WAIT_TIME} -eq ${RETRIES} ] || timeout 14400 bash -c "time sudo ANKA_CREATE_SUSPEND=0 anka create --disk-size 100G --app \"$INSTALLER_LOCATION\" $TEMPLATE_NAME"; do
    sleep $(( $(( NEXT_WAIT_TIME++ )) + 20))
    pgrep -f 'anka create' | sudo xargs kill -9 || true
    pgrep -f 'diskimages-helper' | sudo xargs kill -9 || true
    sudo umount /Volumes/Install* || true
    sudo anka delete --yes "$TEMPLATE_NAME" || true
  done
  [ $NEXT_WAIT_TIME -lt ${RETRIES} ] || exit 5
  modify_uuid $TEMPLATE_NAME $ANKA_BASE_VM_TEMPLATE_UUID
  # Add Registry to CLI (if the registry was installed locally)
  FULL_URL="${URL_PROTOCOL}$CLOUD_REGISTRY_ADDRESS"
  if [[ -z "$(sudo anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME || true)" ]]; then
    if curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null; then
      AWS_USER_DATA="$(curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null)"
      if ! echo "${AWS_USER_DATA}" | grep "404 - Not Found"; then
        FULL_URL="$(echo "${AWS_USER_DATA}" | grep ANKA_CONTROLLER_ADDRESS | cut -d\" -f2 | rev | cut -d: -f2-99 | rev)"
      fi
    fi
    sudo anka registry add $CLOUD_REGISTRY_REPO_NAME ${FULL_URL}:$CLOUD_REGISTRY_PORT
    sudo anka registry list-repos
  fi
  $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME ${TAG_FLAGS}
fi