#!/bin/bash
set -exo pipefail
echo "]] Starting Anka VM Creation"
[[ "${1}" != "--no-anka-create" ]] && MACOS_VERSION=${MACOS_VERSION:-"${1}"}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with: brew install jq" && exit 1
FLAGS="${*}"; set -- # prevent $1 from going into get-macos-with-mist
. ./.misc/get-macos-with-mist.bash
TEMPLATE_NAME="${MACOS_VERSION}${ARCH_EXTENSION}"
INSTALLER_LOCATION="${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${MACOS_VERSION}${EXTENSION}"
if [[ "${FLAGS}" != "--no-anka-create" ]]; then
  # Add Registry to CLI (if the registry was installed locally)
  FULL_URL="${URL_PROTOCOL}$CLOUD_REGISTRY_ADDRESS"
  ADD_REGISTRY=true
  if [[ -z "$(${SUDO} anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME || true)" ]]; then
    IMDS_TOKEN="$(curl -s --connect-timeout 3 -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" || true)"
    # [[ -n "${IMDS_TOKEN}" ]] || (echo "error: no IMDS token obtained from http://169.254.169.254/latest/api/token" && exit 1)
    if [[ -n "${IMDS_TOKEN}" ]] && curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" 2>/dev/null; then
      AWS_USER_DATA="$(curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" 2>/dev/null)"
      if ! echo "${AWS_USER_DATA}" | grep "404 - Not Found"; then
        FULL_URL="$(echo "${AWS_USER_DATA}" | grep ANKA_CONTROLLER_ADDRESS | cut -d\" -f2 | rev | cut -d: -f2-99 | rev)"
      fi
    elif ! curl -s --connect-timeout 1 ${FULL_URL}:$CLOUD_REGISTRY_PORT 2>/dev/null; then
      echo "no running registry at ${FULL_URL}:$CLOUD_REGISTRY_PORT"
      echo "please install the registry before running this script"
      exit
    fi
    if $ADD_REGISTRY; then
      ${SUDO} anka registry add $CLOUD_REGISTRY_REPO_NAME ${FULL_URL}:$CLOUD_REGISTRY_PORT
      ${SUDO} anka registry list-repos
    fi
  fi
  cd $HOME
  # Cleanup already existing Template
  ${SUDO} anka delete --yes $TEMPLATE_NAME &>/dev/null || true
  echo "Installing Apple's Device Support package"
  curl -O https://downloads.veertu.com/anka/DeviceSupport-15.4.pkg
  sudo installer -pkg DeviceSupport-15.4.pkg -target /
  # Create Base Template
  echo "]] Creating $TEMPLATE_NAME using $INSTALLER_LOCATION (please be patient, it can take a while) ..."
  # Retry after an hour and a half just in case macos fails to install for some reason
  RETRIES=4
  NEXT_WAIT_TIME=0
  until [ ${NEXT_WAIT_TIME} -eq ${RETRIES} ] || timeout 14400 bash -c "time ${SUDO} ANKA_CLICK_DEBUG=1 anka ${ANKA_DEBUG} create --disk-size 100G --app \"$INSTALLER_LOCATION\" $TEMPLATE_NAME"; do
    cat ~/Library/Logs/Anka/$(${SUDO} anka show "${TEMPLATE_NAME}" uuid).log
    tail -70 ~/Library/Logs/Anka/anka.log
    sleep $(( $(( NEXT_WAIT_TIME++ )) + 20))
    pgrep -f 'anka create' | sudo xargs kill -9 || true
    pgrep -f 'diskimages-helper' | sudo xargs kill -9 || true
    sudo umount /Volumes/Install* || true
    ${SUDO} anka delete --yes "$TEMPLATE_NAME" || true
  done
  [ $NEXT_WAIT_TIME -lt ${RETRIES} ] || exit 5
  [[ "$(arch)" == "arm64" ]] && ANKA_BASE_VM_TEMPLATE_UUID="${ANKA_BASE_VM_TEMPLATE_UUID_APPLE}" || ANKA_BASE_VM_TEMPLATE_UUID="${ANKA_BASE_VM_TEMPLATE_UUID_INTEL}"
  modify_uuid $TEMPLATE_NAME $ANKA_BASE_VM_TEMPLATE_UUID
  $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME ${TAG_FLAGS}
fi
