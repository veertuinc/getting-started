#!/bin/bash
set -eo pipefail
[[ "$(arch)" == "arm64" ]] && echo "Anka 3.0 (ARM) is currently not supported" && exit 1
MACOS_VERSION=${MACOS_VERSION:-"${1}"}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with: brew install jq" && exit 1
if [[ "$1" == "--no-anka-create" ]] || [[ -z $1 ]]; then
  if [[ -z "${MACOS_VERSION}" ]]; then
    MACOS_VERSION="$(mist list "macOS Monterey" --kind "installer" --latest -o json -q | jq -r '.[].version')"
    [[ ! -d "/Applications/${MACOS_VERSION}.app" ]] && sudo ./.bin/mist download "macOS Monterey" --kind "installer" --application --application-name "${MACOS_VERSION}.app" --output-directory "/Applications"
  else
    [[ ! -d "/Applications/${MACOS_VERSION}.app" ]] && sudo ./.bin/mist download "${MACOS_VERSION}" --kind "installer" --application --application-name "${MACOS_VERSION}.app" --output-directory "/Applications" || echo "Installer already exists"
  fi
  TEMPLATE_NAME="${MACOS_VERSION}"
  INSTALLER_LOCATION="/Applications/${MACOS_VERSION}.app"
fi
if [[ "$1" != "--no-anka-create" ]]; then
  cd $HOME
  # Cleanup already existing Template
  sudo anka delete --yes $TEMPLATE_NAME &>/dev/null || true
  # Create Base Template
  echo "]] Creating $TEMPLATE_NAME using $INSTALLER_LOCATION ..."
  sudo ANKA_CREATE_SUSPEND=0 anka create --disk-size 100G --app "$INSTALLER_LOCATION" $TEMPLATE_NAME
  modify_uuid $TEMPLATE_NAME $ANKA_BASE_VM_TEMPLATE_UUID
  # Add Registry to CLI (if the registry was installed locally)
  FULL_URL="${URL_PROTOCOL}$CLOUD_REGISTRY_ADDRESS"
  if [[ -z "$(sudo anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME || true)" ]]; then
    AWS_USER_DATA="$(curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null)"
    if ! echo "${AWS_USER_DATA}" | grep "404 - Not Found"; then
      FULL_URL="$(echo "${AWS_USER_DATA}" | grep ANKA_CONTROLLER_ADDRESS | cut -d\" -f2 | rev | cut -d: -f2-99 | rev)"
    fi
    sudo anka registry add $CLOUD_REGISTRY_REPO_NAME ${FULL_URL}:$CLOUD_REGISTRY_PORT
    sudo anka registry list-repos
  fi
  $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME
fi