#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../../shared.bash
cleanup() {
  rm -f $STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE
}
sudo anka-controller stop &>/dev/null || true
sudo /Library/Application\ Support/Veertu/Anka/tools/controller/uninstall.sh &>/dev/null || true
sudo rm -rf /Library/Application\ Support/Veertu/Anka/anka-controller
cd $STORAGE_LOCATION
# Download
echo "]] Downloading $CLOUD_NATIVE_PACKAGE"
if [[ -z $1 ]]; then
  trap cleanup EXIT
  curl -S -L -O $CLOUD_DOWNLOAD_URL
  INSTALLER_LOCATION="$STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE"
else
  [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your installer package" && exit 1
  INSTALLER_LOCATION="$1"
fi
sudo installer -pkg $INSTALLER_LOCATION -target /
sudo anka-controller stop &>/dev/null || true
# Configuration
echo "]] Modifying the /usr/local/bin/anka-controllerd configuration"
cat << BLOCK | sudo tee /usr/local/bin/anka-controllerd > /dev/null
#!/bin/bash
ANKA_CERTS_LOCATION="$HOME"
LOG_DIR="/Library/Logs/Veertu/AnkaController"
LISTEN_ADDRESS=":$CLOUD_CONTROLLER_PORT"
DATA_DIR="/Library/Application Support/Veertu/Anka/anka-controller"
REGISTRY_BASE_PATH="/Library/Application Support/Veertu/Anka/registry"
/Library/Application\ Support/Veertu/Anka/bin/anka-controller \\
BLOCK
if [[ $1 == "--certificate-authentication" ]]; then # Certificate Auth
URL_PROTOCOL="https://"
EXTRA_NOTE="Certificates have been generated and are stored under $HOME
Documentation about certificate authentication can be found at https://ankadocs.veertu.com/docs/anka-build-cloud/advanced-security-features/certificate-authentication/"
echo "]] Generating Certificates"
$SCRIPT_DIR/create-ca-and-controller-certs.bash # Generate all of the certs you'll need
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
--standalone \\
--listen_addr "\$LISTEN_ADDRESS" \\
--enable-central-logging \\
--log_dir "\$LOG_DIR" \\
--data-dir "\$DATA_DIR" \\
--run-registry \\
--registry-base-path  "\$REGISTRY_BASE_PATH" \\
--registry-listen-address "$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT" \\
--anka-registry "$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT" \\
--use-https \\
--enable-auth \\
--ca-cert \$ANKA_CERTS_LOCATION/anka-ca-crt.pem \\
--server-cert \$ANKA_CERTS_LOCATION/anka-controller-crt.pem \\
--server-key \$ANKA_CERTS_LOCATION/anka-controller-key.pem
BLOCK
elif [[ $1 == "--root-token-authentication" ]]; then # Root Token Auth
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
--standalone \\
--listen_addr "\$LISTEN_ADDRESS" \\
--enable-central-logging \\
--log_dir "\$LOG_DIR" \\
--data-dir "\$DATA_DIR" \\
--run-registry \\
--registry-base-path  "\$REGISTRY_BASE_PATH" \\
--registry-listen-address "$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT" \\
--anka-registry "$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT" \\
--root-token 1111111111
BLOCK
else ## Basic
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
--standalone \\
--listen_addr "\$LISTEN_ADDRESS" \\
--enable-central-logging \\
--log_dir "\$LOG_DIR" \\
--data-dir "\$DATA_DIR" \\
--run-registry \\
--registry-base-path  "\$REGISTRY_BASE_PATH" \\
--registry-listen-address "$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT" \\
--anka-registry "$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
BLOCK
fi
echo "]] Starting the Anka Build Cloud Controller & Registry"
sudo anka-controller start &>/dev/null || true
ANKA_CONTROLLER_STATUS=$(sudo anka-controller status)
if [[ $ANKA_CONTROLLER_STATUS =~ "is Running" ]]; then
  echo $ANKA_CONTROLLER_STATUS
else
  echo $ANKA_CONTROLLER_STATUS
  echo "Something is wrong... Checking logs..."
  echo "/Library/Logs/Veertu/AnkaController/anka-controller.INFO"
  tail -20 /Library/Logs/Veertu/AnkaController/anka-controller.INFO
  echo "/Library/Logs/Veertu/AnkaController/anka-controller.ERROR"
  tail -20 /Library/Logs/Veertu/AnkaController/anka-controller.ERROR
  echo "/Library/Logs/Veertu/AnkaController/anka-controller.WARNING"
  tail -20 /Library/Logs/Veertu/AnkaController/anka-controller.WARNING
  exit 1
fi
# Set Hosts
modify_hosts $CLOUD_CONTROLLER_ADDRESS &>/dev/null
modify_hosts $CLOUD_REGISTRY_ADDRESS &>/dev/null
# Join cluster
echo "]] Joining this machine (Node) to the Cloud"
if [[ "$(sudo ankacluster status)" =~ "is running" ]]; then
  WAIT=0
  sudo ankacluster disjoin &
  while ps -p $! | grep $! &>/dev/null; do
    echo "The current machine (Node) is joined to a cluster. Waiting for it to disjoin..."
    if [[ $WAIT < 10 ]]; then
      sleep 20
    else
      echo "Something is taking too long to disjoin... Forcfully disjoining"
      sudo kill -9 $(pgrep anka_agent) &>/dev/null || true
      sudo kill -9 $(pgrep anka_agent_helper) &>/dev/null || true
    fi
    ((WAIT++))
  done
fi
sleep 20
sudo ankacluster join ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT
#
echo "============================================================================="
echo "Controller UI:  $URL_PROTOCOL$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT"
echo "Registry:       $URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
echo "Documentation:  https://ankadocs.veertu.com/docs/getting-started/macos/"
if [[ ! -z $EXTRA_NOTE ]]; then
  echo "$EXTRA_NOTE
  "
fi