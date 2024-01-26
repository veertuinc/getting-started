#!/usr/bin/env bash
set -exo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
WORKDIR="/tmp"
cd "${WORKDIR}"
[[ -n "$(command -v jq)" ]] || brew install jq
# [[ -n "$(command -v mist)" ]] || brew install mist
# [[ -n "$(mist --version)" && "$(mist --version | cut -d. -f1,2 | awk '{print $1}' | sed 's/\.//g')" -lt 18 ]] && echo "You must install a version of mist >= 1.8" && exit 1
if [[ -n "$(mist --version)" && "$(mist --version | cut -d. -f1,2 | awk '{print $1}' | sed 's/\.//g')" -ne 20 ]]; then
  brew remove mist || true
  sudo rm -f /usr/local/bin/mist || true
  curl -L -O https://github.com/ninxsoft/mist-cli/releases/download/v2.0/mist-cli.2.0.pkg
  sudo installer -pkg "${WORKDIR}/mist-cli.2.0.pkg" -target /
fi
# curl --fail --silent -L -O https://raw.githubusercontent.com/veertuinc/getting-started/master/.bin/mist && sudo chmod +x mist
[[ -z "${MACOS_VERSION}" ]] && MACOS_VERSION=${1:-"Sonoma"}
MIST_KIND=${MIST_KIND:-"installer"}
# Support >= 1.8
MIST_OPTIONS="${MIST_KIND} ${MACOS_VERSION}"
[[ "$(arch)" != "arm64" ]] && MIST_APPLICATION="application"
MIST_COMPATIBLE_FLAG="--compatible"
MIST_NAME_OPTION="--application-name"
if [[ "$(arch)" == "arm64" ]]; then
  MIST_KIND="firmware"
  MIST_NAME_OPTION="--firmware-name"
  MIST_APPLICATION="" # firmware has no need for this
fi
if [[ "${MACOS_VERSION}" =~ ^[0-9]+.[0-9]+$ ]]; then
  MIST_LIST_RESULTS="$(mist list ${MIST_KIND} ${MACOS_VERSION} ${MIST_COMPATIBLE_FLAG} -o json -q)"
  FOUND_MIST_MACOS_BUILD="$(echo "${MIST_LIST_RESULTS}" | jq -r '.[].build' | tail -1)"
  FOUND_MIST_MACOS_VERSION="$(echo "${MIST_LIST_RESULTS}" | jq -r '.[].version' | tail -1)"
else
  MIST_LIST_RESULTS="$(mist list ${MIST_KIND} ${MACOS_VERSION} ${MIST_COMPATIBLE_FLAG} --latest -o json -q)"
  FOUND_MIST_MACOS_BUILD="$(echo "${MIST_LIST_RESULTS}" | jq -r '.[].build')"
  FOUND_MIST_MACOS_VERSION="$(echo "${MIST_LIST_RESULTS}" | jq -r '.[].version')"
fi
MIST_OPTIONS="${MIST_KIND} ${FOUND_MIST_MACOS_BUILD} ${MIST_APPLICATION}"
INSTALL_MACOS_DIR="/Applications"
[[ "${MIST_KIND}" == "firmware" ]] && EXTENSION=".ipsw" || EXTENSION=".app"
PREFIX_FOR_INSTALLERS="macos-"
# Clean up older installers to keep the disk usage low
ALLOWED_USAGE_GB=33
while true; do
  if [ $(du -gc ${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}* | grep total$ | awk '{ print $1 }') -gt ${ALLOWED_USAGE_GB} ]; then
    echo "Usage of installers under ${INSTALL_MACOS_DIR} has exceeded ${ALLOWED_USAGE_GB}GB. We will now delete an installer to make room..."
    INSTALLER_TO_CLEANUP="$(ls -tl ${INSTALL_MACOS_DIR} | grep ${PREFIX_FOR_INSTALLERS} | sort -k6M -k7n | awk '{ print $9 }' | head -1)"
    sudo rm -rf "${INSTALL_MACOS_DIR}/${INSTALLER_TO_CLEANUP}"
  else
    break
  fi
done
# Download the installer
if [[ ! -e "${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${FOUND_MIST_MACOS_VERSION}${EXTENSION}" ]]; then
  if [[ -z "${FOUND_MIST_MACOS_VERSION}" ]]; then
    if [[ "${MIST_KIND}" == "installer" ]]; then
      echo "No versions found in either apple's mirrors..."
      exit 3
    else
      echo "No versions found in ipsw.me/mist..."
      exit 3
    fi
  else
    LOG_LOC="${WORKDIR}/mist-download.log"
    echo "Downloading macOS ${FOUND_MIST_MACOS_VERSION} (${FOUND_MIST_MACOS_BUILD}) using mist. This will not output anything until it's finished and can sometimes take quite a while. You can tail ${LOG_LOC} to check the progress."
    sudo mist download ${MIST_OPTIONS} ${MIST_APPLICATION} ${MIST_NAME_OPTION} "${PREFIX_FOR_INSTALLERS}%VERSION%${EXTENSION}" ${MIST_COMPATIBLE_FLAG} --output-directory "${INSTALL_MACOS_DIR}" > "${LOG_LOC}" # jenkins log becomes unreasonably large if we show all of the output while downloading
    sudo tail -50 "${LOG_LOC}"
    sudo chmod 644 ${INSTALL_MACOS_DIR}/*.ipsw 2>/dev/null || true
  fi
else
  echo "Mac os installer exists -- nothing to do"
fi
MACOS_VERSION="${FOUND_MIST_MACOS_VERSION}"
