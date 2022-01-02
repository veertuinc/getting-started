#!/bin/bash
set -eo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd $SCRIPT_DIR
. ./shared.bash
# cleanup() {
#   sudo anka delete --yes $TEMPLATE_NAME || true
# }
# trap cleanup ERR INT
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with: brew install jq" && exit 1
TEMP_DIR="/tmp/anka-mac-resources"
MOUNT_DIR="$TEMP_DIR/mount"
sudo chmod -R 777 $TEMP_DIR || true
mkdir -p $MOUNT_DIR
rm -f $TEMP_DIR/Install_*.sparseimage
cd $TEMP_DIR
if [[ "$1" == "--no-anka-create" ]] || [[ -z $1 ]]; then # interactive installer
  # Download the macOS installer script and prepare the install.app
  echo "]] Downloading Mac Installer .app (requires root) ..."
  cp $SCRIPT_DIR/.misc/download-macos-installer.py $TEMP_DIR/
  sudo ./download-macos-installer.py --raw --workdir $TEMP_DIR/
  INSTALL_IMAGE=$(basename $TEMP_DIR/Install_*.sparseimage)
  TEMPLATE_NAME=${TEMPLATE_NAME:-"$(echo $INSTALL_IMAGE | sed -n 's/.*macOS_\([0-9][0-9]\..*\)-.*/\1/p')"}
  [[ "${#TEMPLATE_NAME}" -eq 4 ]] && TEMPLATE_NAME="${TEMPLATE_NAME}.0" # bug fix for 2.5.3 and 11.6 named templates
  echo "]] Mounting $INSTALL_IMAGE to $MOUNT_DIR ..."
  sudo hdiutil attach $INSTALL_IMAGE -mountpoint $MOUNT_DIR
  INSTALL_APP=$(basename $MOUNT_DIR/Applications/Install*.app)
  INSTALLER_LOCATION="/Applications/$INSTALL_APP"
  sudo cp -rf "$MOUNT_DIR/Applications/$INSTALL_APP" /Applications/
  sudo hdiutil detach $MOUNT_DIR -force
else
  [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your install .app" && exit 1
  TEMPLATE_NAME=${TEMPLATE_NAME:-"$(echo $1 | sed -n 's/.*macOS \(.*\).app/\1/p' | sed 's/ /-/g')"}
  [[ -z $TEMPLATE_NAME ]] && echo "Did you specify the path to an macOS installer .app?" && exit 1
  INSTALLER_LOCATION="$1"
fi
echo "]] Installer placed at $INSTALLER_LOCATION"
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
  if AWS_USER_DATA="$(curl -s --connect-timeout 3 http://169.254.169.254/latest/user-data 2>/dev/null)"; then
    FULL_URL="$(echo "${AWS_USER_DATA}" | grep ANKA_CONTROLLER_ADDRESS | cut -d\" -f2)"
  fi
  if [[ -z "$(sudo anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME || true)" ]]; then
    sudo anka registry add $CLOUD_REGISTRY_REPO_NAME ${FULL_URL}:$CLOUD_REGISTRY_PORT
    sudo anka registry list-repos
  fi
  $SCRIPT_DIR/create-vm-template-tags.bash $TEMPLATE_NAME
fi