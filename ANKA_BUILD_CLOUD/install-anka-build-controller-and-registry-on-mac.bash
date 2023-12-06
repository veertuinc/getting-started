#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
# [[ "$(arch)" == "arm64" ]] && sudo softwareupdate --install-rosetta
# Cleanup
cleanup() {
  rm -f "${STORAGE_LOCATION}/${CLOUD_NATIVE_MACOS_CONTROLLER_PACKAGE}"
  rm -f "${STORAGE_LOCATION}/${CLOUD_NATIVE_MACOS_REGISTRY_PACKAGE}"
}
# Warn about node being joined
if [[ "$(sudo ankacluster status)" =~ "is running" ]]; then
  echo "You have this machine (node) joined to the Cloud! Please disjoin before uninstalling or reinstalling with: sudo ankacluster disjoin"
  exit 1
fi
echo "]] Cleaning up the previous Anka Cloud installation"
sudo anka-controller stop &>/dev/null || true
sudo anka-registry stop &>/dev/null || true
sudo /Library/Application\ Support/Veertu/Anka/tools/controller/uninstall.sh 2>/dev/null || true
sudo /Library/Application\ Support/Veertu/Anka/tools/registry/uninstall.sh 2>/dev/null || true
sudo rm -rf /Library/Application\ Support/Veertu/Anka/anka-controller
sudo rm -rf /tmp/AnkaAgent.pkg
# Install
if [[ $1 != "--uninstall" ]]; then
  cd $STORAGE_LOCATION
  # Download
  if [[ -z $1 ]]; then
    trap cleanup EXIT
    echo "]] Downloading ${CLOUD_NATIVE_MACOS_CONTROLLER_PACKAGE}"
    curl -S -L -O "$CLOUDFRONT_URL/$CLOUD_NATIVE_MACOS_CONTROLLER_PACKAGE"
    CONTROLLER_INSTALLER_LOCATION="$STORAGE_LOCATION/$CLOUD_NATIVE_MACOS_CONTROLLER_PACKAGE"
      echo "]] Downloading ${CLOUD_NATIVE_MACOS_REGISTRY_PACKAGE}"
    curl -S -L -O "$CLOUDFRONT_URL/$CLOUD_NATIVE_MACOS_REGISTRY_PACKAGE"
    REGISTRY_INSTALLER_LOCATION="$STORAGE_LOCATION/$CLOUD_NATIVE_MACOS_REGISTRY_PACKAGE"
  # else
  #   [[ "${1:0:1}" != "/" ]] && echo "Ensure you're using the absolute path to your installer package" && exit 1
  #   INSTALLER_LOCATION="$1"
  #   echo "]] Installing $INSTALLER_LOCATION"
  fi
  sudo installer -pkg $CONTROLLER_INSTALLER_LOCATION -target /
  sudo anka-controller stop &>/dev/null || true
  sudo installer -pkg $REGISTRY_INSTALLER_LOCATION -target /
  sudo anka-registry stop &>/dev/null || true
  # Configuration
  echo "]] Modifying the /usr/local/bin/anka-controllerd configuration"
cat << BLOCK | sudo tee /usr/local/bin/anka-controllerd > /dev/null
#!/usr/bin/env bash
export ANKA_STANDALONE="true"
export ANKA_LISTEN_ADDR="0.0.0.0:${CLOUD_CONTROLLER_PORT}"
export ANKA_DATA_DIR="${CLOUD_CONTROLLER_DATA_DIR}"
export ANKA_ENABLE_CENTRAL_LOGGING="true"
export ANKA_LOG_DIR="${CLOUD_CONTROLLER_LOG_DIR}"
\${ANKA_USE_HTTPS:-false} && SCHEME="https://" || SCHEME="http://"
export ANKA_ANKA_REGISTRY="\${SCHEME}anka.registry:8089"
/Library/Application\ Support/Veertu/Anka/bin/anka-controller
BLOCK
cat << BLOCK | sudo tee /usr/local/bin/anka-registryd > /dev/null
#!/usr/bin/env bash
export ANKA_LISTEN_ADDR=":8089"
export ANKA_LOG_DIR="/Library/Logs/Veertu/AnkaRegistry"
export ANKA_BASE_PATH="${CLOUD_REGISTRY_STORAGE_LOCATION}"
export ANKA_ENABLE_CENTRAL_LOGGING="true"
/Library/Application\ Support/Veertu/Anka/bin/anka-registry
BLOCK
#   if [[ $1 == "--certificate-authentication" ]]; then # Certificate Auth
#     URL_PROTOCOL="https://"
#     EXTRA_NOTE="Certificates have been generated and are stored under $HOME
#     Documentation about certificate authentication can be found at https://docs.veertu.com/anka/intel/anka-build-cloud/advanced-security-features/certificate-authentication/"
#     echo "]] Generating Certificates"
#     $SCRIPT_DIR/generate-certs.bash # Generate all of the certs you'll need
# cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
# export ANKA_USE_HTTPS="true"
# export ANKA_SKIP_TLS_VERIFICATION="true"
# export ANKA_SERVER_CERT="$HOME/anka-controller-crt.pem"
# export ANKA_SERVER_KEY="$HOME/anka-controller-key.pem"
# export ANKA_CA_CERT="$HOME/anka-ca-crt.pem"
# export ANKA_CLIENT_CERT="$HOME/anka-controller-crt.pem"
# export ANKA_CLIENT_CERT_KEY="$HOME/anka-controller-key.pem"
# BLOCK
#   elif [[ $1 == "--root-token-authentication" ]]; then # Root Token Auth
# cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null
# export ANKA_REGISTRY_LISTEN_ADDRESS="$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
# export ANKA_ANKA_REGISTRY="$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
# export ANKA_ENABLE_AUTH="true"
# export ANKA_ROOT_TOKEN="1111111111"
# BLOCK
#   fi
# cat << BLOCK | sudo tee -a /usr/local/bin/anka-controllerd > /dev/null 
# export ANKA_REGISTRY_LISTEN_ADDRESS="$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
# export ANKA_ANKA_REGISTRY="$URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
# /Library/Application\ Support/Veertu/Anka/bin/anka-controller
# BLOCK
  echo "]] Starting the Anka Build Cloud Controller & Registry"
  sudo anka-controller start &>/dev/null || true
  sudo anka-registry start &>/dev/null || true
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
  # Ensure we have the right Anka Agent version installed (for rolling back versions)
  if [[ "$(arch)" == "arm64" ]]; then
    curl -O ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT/pkg/AnkaAgentArm.pkg -o /tmp/ && sudo installer -pkg /tmp/AnkaAgentArm.pkg -tgt /
  else
    curl -O ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT/pkg/AnkaAgent.pkg -o /tmp/ && sudo installer -pkg /tmp/AnkaAgent.pkg -tgt /
  fi
  echo "sudo ankacluster join ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT"
  sudo ankacluster join ${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT --groups "gitlab-test-group-env" || true
  #
  echo "============================================================================="
  echo "Controller UI:  $URL_PROTOCOL$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT"
  echo "Registry:       $URL_PROTOCOL$CLOUD_REGISTRY_ADDRESS:$CLOUD_REGISTRY_PORT"
  echo "Documentation:  https://docs.veertu.com/anka/anka-build-cloud/"
  if [[ ! -z $EXTRA_NOTE ]]; then
    echo "$EXTRA_NOTE
    "
  fi
fi