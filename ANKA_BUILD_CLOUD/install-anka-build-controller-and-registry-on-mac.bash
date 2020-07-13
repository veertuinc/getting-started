#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
# Cleanup
cleanup() {
  rm -f $STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE
}
# Warn about node being joined
if [[ "$(sudo ankacluster status)" =~ "is running" ]]; then
  echo "You have this machine (node) joined to the Cloud! Please disjoin before uninstalling or reinstalling with: sudo ankacluster disjoin"
  exit 1
fi
echo "]] Cleaning up the previous Anka Cloud installation"
sudo anka-controller stop &>/dev/null || true
sudo /Library/Application\ Support/Veertu/Anka/tools/controller/uninstall.sh 2>/dev/null || true
sudo rm -rf /Library/Application\ Support/Veertu/Anka/anka-controller
# Install
if [[ $1 != "--uninstall" ]]; then
  cd $STORAGE_LOCATION
  # Download
  if [[ -z $1 ]]; then
    echo "]] Downloading $CLOUD_NATIVE_PACKAGE"
    trap cleanup EXIT
    curl -S -L -O $CLOUD_DOWNLOAD_URL
    INSTALLER_LOCATION="$STORAGE_LOCATION/$CLOUD_NATIVE_PACKAGE"
  else
    [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your installer package" && exit 1
    INSTALLER_LOCATION="$1"
    echo "]] Installing $INSTALLER_LOCATION"
  fi
  sudo installer -pkg $INSTALLER_LOCATION -target /
  sudo anka-controller stop &>/dev/null || true
  # Configuration
  echo "]] Modifying the /usr/local/bin/anka-controllerd configuration"
cat << BLOCK | sudo tee /usr/local/bin/anka-controllerd > /dev/null
#!/bin/bash
export ANKA_STANDALONE="true"
export ANKA_LISTEN_ADDR=":$CLOUD_CONTROLLER_PORT"
export ANKA_DATA_DIR="$CLOUD_CONTROLLER_DATA_DIR"
export ANKA_ENABLE_CENTRAL_LOGGING="true"
export ANKA_LOG_DIR="$CLOUD_CONTROLLER_LOG_DIR"
export ANKA_RUN_REGISTRY="true"
export ANKA_REGISTRY_BASE_PATH="$CLOUD_REGISTRY_BASE_PATH"
BLOCK
  if [[ $1 == "--certificate-authentication" ]]; then # Certificate Auth
    URL_PROTOCOL="https://"
    EXTRA_NOTE="Certificates have been generated and are stored under $HOME
    Documentation about certificate authentication can be found at https://ankadocs.veertu.com/docs/anka-build-cloud/advanced-security-features/certificate-authentication/"
    echo "]] Generating Certificates"
    $SCRIPT_DIR/create-ca-and-controller-certs.bash # Generate all of the certs you'll need
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
export ANKA_USE_HTTPS="false"
export ANKA_SKIP_TLS_VERIFICATION="false"
export ANKA_SERVER_CERT="/mnt/cert/anka-controller-crt.pem"
export ANKA_SERVER_KEY="/mnt/cert/anka-controller-key.pem"
export ANKA_CA_CERT="/mnt/cert/anka-ca-crt.pem"
export ANKA_CERTS_LOCATION="\$HOME"
export ANKA_ENABLE_AUTH="true"
BLOCK
  elif [[ $1 == "--root-token-authentication" ]]; then # Root Token Auth
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
export ANKA_REGISTRY_LISTEN_ADDRESS="$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
export ANKA_ANKA_REGISTRY="$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
export ANKA_ENABLE_AUTH="true"
export ANKA_ROOT_TOKEN="1111111111"
BLOCK
  fi
cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null 
export ANKA_REGISTRY_LISTEN_ADDRESS="$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
export ANKA_ANKA_REGISTRY="$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
/Library/Application\ Support/Veertu/Anka/bin/anka-controller
BLOCK
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
  echo "]] Joining this machine (Node) to the Cloud"
  sleep 20
  sudo ankacluster join ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT || true
  #
  echo "============================================================================="
  echo "Controller UI:  $URL_PROTOCOL$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT"
  echo "Registry:       $URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
  echo "Documentation:  https://ankadocs.veertu.com/docs/getting-started/macos/"
  if [[ ! -z $EXTRA_NOTE ]]; then
    echo "$EXTRA_NOTE
    "
  fi
fi