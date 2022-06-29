#!/usr/bin/env bash
set -eo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
WORKDIR="/tmp"
cd "${WORKDIR}"
[[ -n "$(command -v jq)" ]] || brew install jq
[[ -n "$(command -v mist)" ]] || brew install mist
# curl --fail --silent -L -O https://raw.githubusercontent.com/veertuinc/getting-started/master/.bin/mist && sudo chmod +x mist
[[ -z "${MACOS_VERSION}" ]] && MACOS_VERSION=${1:-"Monterey"}
[[ -n "${1}" && $(echo ${MACOS_VERSION} | tr -dc . | awk '{ print length }') != 2 ]] && echo "Versions must have three sections (example: 12.2.1)" && exit 2
MIST_KIND=${MIST_KIND:-"installer"}
# Support >= 1.8
MIST_OPTIONS="${MACOS_VERSION} --kind ${MIST_KIND}"
MIST_APPLICATION="--application"
if [[ "$(arch)" == "arm64" ]]; then
  MIST_KIND="firmware"
  MIST_APPLICATION="" # firmware has no need for this
fi
if [[ -n "$(mist version | grep "1.8.* (Latest")" ]]; then
  MIST_OPTIONS="${MIST_KIND} ${MACOS_VERSION}"
  [[ "$(arch)" != "arm64" ]] && MIST_APPLICATION="application"
fi
FOUND_MIST_MACOS_VERSION="$(mist list ${MIST_OPTIONS} --compatible --latest -o json -q | jq -r '.[].version')"
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
if [[ ! -d "${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${FOUND_MIST_MACOS_VERSION}${EXTENSION}" ]]; then
  if [[ -z "${FOUND_MIST_MACOS_VERSION}" ]]; then
    if [[ "${MIST_KIND}" == "installer" ]]; then
      echo "No version found in apple's mirrors through mist..."
      exit 2
    else
      echo "No versions found in ipsw.me/mist..."
      exit 3
    fi

  else
    LOG_LOC="${WORKDIR}/mist-download.log"
    echo "Downloading macOS ${MACOS_VERSION} using mist. This will not output anything until it's finished and can sometimes take quite a while. You can tail ${LOG_LOC} to check the progress."
    sudo mist download ${MIST_OPTIONS} ${MIST_APPLICATION} --application-name "${PREFIX_FOR_INSTALLERS}%VERSION%${EXTENSION}" --compatible --output-directory "${INSTALL_MACOS_DIR}" > "${LOG_LOC}" # jenkins log becomes unreasonably large if we show all of the output while downloading
    sudo tail -50 "${LOG_LOC}"
    sudo chmod 644 ${INSTALL_MACOS_DIR}/*.ipsw 2>/dev/null || true
  fi
else
  echo "Mac os installer exists -- nothing to do"
fi
MACOS_VERSION="${FOUND_MIST_MACOS_VERSION}"
