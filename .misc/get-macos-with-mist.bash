#!/usr/bin/env bash
set -exo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin
cd /tmp
[[ -n "$(command -v jq)" ]] || brew install jq
[[ -n "$(command -v mist)" ]] || brew install mist
# curl --fail --silent -L -O https://raw.githubusercontent.com/veertuinc/getting-started/master/.bin/mist && sudo chmod +x mist
[[ -z "${MACOS_VERSION}" ]] && MACOS_VERSION=${1:-"Monterey"}
MIST_KIND=${MIST_KIND:-"installer"}
[[ "$(arch)" == "arm64" ]] && MIST_KIND="firmware"
MACOS_VERSION="$(mist list "${MACOS_VERSION}" --kind "${MIST_KIND}" --latest -o json -q | jq -r '.[].version')"
INSTALL_MACOS_DIR="/Applications"
EXTENSION=".app"
PREFIX_FOR_INSTALLERS="macos-"
[[ "${MIST_KIND}" == "firmware" ]] && EXTENSION=".ipsw"
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
if [[ ! -d "${INSTALL_MACOS_DIR}/${PREFIX_FOR_INSTALLERS}${MACOS_VERSION}${EXTENSION}" ]]; then
  echo "Downloading macOS ${MACOS_VERSION} using mist. This will not output anything until it's finished and can sometimes take quite a while. You can tail mist-download.log to check the progress."
  sudo mist download "${MACOS_VERSION}" --kind "${MIST_KIND}" --application --application-name "${PREFIX_FOR_INSTALLERS}%VERSION%${EXTENSION}" --output-directory "${INSTALL_MACOS_DIR}" &> mist-download.log # jenkins log becomes unreasonably large if we show all of the output while downloading
  tail -50 mist-download.log
else
  echo "Mac os installer exists -- nothing to do"
fi
