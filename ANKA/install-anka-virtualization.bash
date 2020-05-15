#!/bin/bash
set -eo pipefail
[[ -z $1 ]] && echo "Please include a license as the first argument!" && exit 1
ANKA_LICENSE=$1
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
cleanup() {
  rm -f $STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE
}
trap cleanup EXIT
sudo /Library/Application\ Support/Veertu/Anka/tools/uninstall.sh &>/dev/null || true
cd $STORAGE_LOCATION
# Download
echo "]] Downloading $ANKA_VIRTUALIZATION_PACKAGE"
curl -S -L -O $ANKA_VIRTUALIZATION_DOWNLOAD_URL
# Install
echo "]] Installing $STORAGE_LOCATION/$ANKA_VIRTUALIZATION_PACKAGE"
if [[ $1 == "-nested-virtualization" ]]; then
  sudo installer -applyChoiceChangesXML nanka.xml -pkg $STORAGE_LOCATION/$ANKA_VIRTUALIZATION_PACKAGE -target /
else
  sudo installer -pkg $STORAGE_LOCATION/$ANKA_VIRTUALIZATION_PACKAGE -target /
fi
# Licensing
echo "]] Activating license"
sudo anka license activate $ANKA_LICENSE
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
echo "Documentation:  https://ankadocs.veertu.com/docs/anka-cli/"