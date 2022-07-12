#!/bin/bash
set -exo pipefail
echo "]] Starting Anka VM Creation"
MACOS_VERSION=${MACOS_VERSION:-"${1}"}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with: brew install jq" && exit 1
. ./.misc/get-macos-with-mist.bash
[[ "$(arch)" == "arm64" ]] && SUDO="" || SUDO="sudo" # Can't open the anka viewer to install macos and addons as sudo.
TEMPLATE_NAME="${MACOS_VERSION}"
INSTALLER_LOCATION="${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${MACOS_VERSION}${EXTENSION}"
if [[ "$1" != "--no-anka-create" ]]; then
  # Add Registry to CLI (if the registry was installed locally)
  FULL_URL="${URL_PROTOCOL}$CLOUD_REGISTRY_ADDRESS"
  ADD_REGISTRY=true
  if [[ -z "$(${SUDO} anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME || true)" ]]; then
    if curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null; then
      AWS_USER_DATA="$(curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null)"
      if ! echo "${AWS_USER_DATA}" | grep "404 - Not Found"; then
        FULL_URL="$(echo "${AWS_USER_DATA}" | grep ANKA_CONTROLLER_ADDRESS | cut -d\" -f2 | rev | cut -d: -f2-99 | rev)"
      fi
    elif ! curl -s --connect-timeout 1 ${FULL_URL}:$CLOUD_REGISTRY_PORT 2>/dev/null; then
      echo "no running registry at ${FULL_URL}:$CLOUD_REGISTRY_PORT"
      ADD_REGISTRY=false
    fi
    if $ADD_REGISTRY; then
      ${SUDO} anka registry add $CLOUD_REGISTRY_REPO_NAME ${FULL_URL}:$CLOUD_REGISTRY_PORT
      ${SUDO} anka registry list-repos
    fi
  fi
  cd $HOME
  # Cleanup already existing Template
  ${SUDO} anka delete --yes $TEMPLATE_NAME &>/dev/null || true
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
    ${SUDO} anka delete --yes "$TEMPLATE_NAME" || true
  done
  [ $NEXT_WAIT_TIME -lt ${RETRIES} ] || exit 5
  [[ "$(arch)" == "arm64" ]] && ANKA_BASE_VM_TEMPLATE_UUID="${ANKA_BASE_VM_TEMPLATE_UUID_APPLE}" || ANKA_BASE_VM_TEMPLATE_UUID="${ANKA_BASE_VM_TEMPLATE_UUID_INTEL}"
  modify_uuid $TEMPLATE_NAME $ANKA_BASE_VM_TEMPLATE_UUID
  if [[ "$(arch)" == "arm64" ]]; then
    echo "At the moment the automated macOS installation process is not possible for Anka 3/Apple processors. You need to manually start the VM with anka start -uv {VMNAME} and finish the installation. \
      Don't forget to install the Anka addons! See https://docs.veertu.com/anka/apple/getting-started/creating-your-first-vm/#3-start-the-vm-and-finish-the-macos-install for more information."
    echo "Once you're done, stop the VM and run $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME ${TAG_FLAGS}"
    exit
  fi
  $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME ${TAG_FLAGS}
fi