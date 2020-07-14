#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
# Cleanup
cleanup() {
  rm -f $STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE
}
trap cleanup EXIT
echo "]] Cleaning up the previous Anka Virtualization CLI installation"
sudo /Library/Application\ Support/Veertu/Anka/tools/uninstall.sh -f 2>/dev/null || true
# Install
if [[ $1 != "--uninstall" ]]; then
  cd $STORAGE_LOCATION
  # Download
  if [[ -z $1 ]]; then
    echo "]] Downloading $ANKA_VIRTUALIZATION_PACKAGE"
    curl -S -L -O $ANKA_VIRTUALIZATION_DOWNLOAD_URL
    trap cleanup EXIT
    INSTALLER_LOCATION="$STORAGE_LOCATION/$ANKA_VIRTUALIZATION_PACKAGE"
  else
    [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your installer package" && exit 1
    INSTALLER_LOCATION="$1"
    echo "]] Installing $INSTALLER_LOCATION"
  fi
  # Install
  if [[ $1 == "-nested-virtualization" ]]; then
    sudo installer -applyChoiceChangesXML nanka.xml -pkg $INSTALLER_LOCATION -target /
  else
    sudo installer -pkg $INSTALLER_LOCATION -target /
  fi
  # Licensing
  echo "]] Activating license"
  if [[ -z $ANKA_LICENSE ]]; then
    while true; do
      read -p "Input your Anka license: " ANKA_LICENSE
      case $ANKA_LICENSE in
        "" ) echo "Want to type something?";;
        "skip" ) echo "skipping license activate"; break;;
        * ) break;;
      esac
    done
  fi
  sudo anka license activate -f $ANKA_LICENSE
  sudo anka license accept-eula || true
  sudo anka license validate
  #
  ANKA_STATUS=$(sudo anka version)
  if [[ $ANKA_STATUS =~ "Anka Build" ]]; then
    echo $ANKA_STATUS
  else
    echo $ANKA_STATUS
    echo "Something is wrong... Checking logs..."
    echo "tail -20 /Library/Logs/Anka/*"
    tail -20 /Library/Logs/Anka/*
    exit 1
  fi
  echo "================================================================"
  echo "Documentation: https://ankadocs.veertu.com/docs/anka-build-cloud/virtualization-cli/"
fi