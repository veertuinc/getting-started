[[ $DEBUG == true ]] && set -x

STORAGE_LOCATION=${STORAGE_LOCATION:-"/tmp"}
URL_PROTOCOL=${URL_PROTOCOL:-"http://"}

if [[ "$(uname)" == "Darwin" ]]; then
  if tty -s; then # Disable if the shell isn't interactive (avoids: tput: No value for $TERM and no -T specified)
    export COLOR_NC=$(tput sgr0) # No Color
    export COLOR_RED=$(tput setaf 1)
    export COLOR_GREEN=$(tput setaf 2)
    export COLOR_YELLOW=$(tput setaf 3)
    export COLOR_BLUE=$(tput setaf 4)
    export COLOR_MAGENTA=$(tput setaf 5)
    export COLOR_CYAN=$(tput setaf 6)
    export COLOR_WHITE=$(tput setaf 7)
  fi
fi

error() {
  echo "${COLOR_RED}ERROR: $* ${COLOR_NC}"
  exit 50
}

warning() {
  echo "${COLOR_YELLOW}WARNING: $* ${COLOR_NC}"
}

obtain_anka_license() {
  if [[ -z "${ANKA_LICENSE}" ]]; then
    while true; do
      read -p "Input your Anka license (type \"skip\" to skip this): " ANKA_LICENSE
      case "${ANKA_LICENSE}" in
        "" ) echo "Want to type something?";;
        "skip" ) echo "skipping license activate"; break;;
        * ) break;;
      esac
    done
  fi
}

JENKINS_PLUGIN_VERSION="2.6.0"
JENKINS_PIPELINE_PLUGIN_VERSION="1.8.4"
CREDENTIALS_PLUGIN_VERSION="2.5"
GITHUB_PLUGIN_VERSION="1.33.1"
GITLAB_ANKA_RUNNER_VERSION=${GITLAB_ANKA_RUNNER_VERSION:-"1.4.0"}
GITLAB_RELEASE_TYPE=${GITLAB_RELEASE_TYPE:-"ce"}
GITLAB_DOCKER_TAG_VERSION=${GITLAB_DOCKER_TAG_VERSION:-"14.0.5-$GITLAB_RELEASE_TYPE.0"}
CLOUD_NATIVE_PACKAGE=${CLOUD_NATIVE_PACKAGE:-"AnkaControllerRegistry-1.19.0-7c1c1424.pkg"}
CLOUD_DOCKER_TAR=${CLOUD_DOCKER_TAR:-"anka-controller-registry-1.19.0-7c1c1424.tar.gz"}
ANKA_VIRTUALIZATION_PACKAGE=${ANKA_VIRTUALIZATION_PACKAGE:-"Anka-2.5.3.135.pkg"}
TEAMCITY_VERSION="2020.2.3"
PROMETHEUS_BINARY_VERSION=${PROMETHEUS_BINARY_VERSION:-"2.2.2"}

CLOUDFRONT_URL="https://downloads.veertu.com/anka"

[[ "$(uname)" == "Darwin" ]] && DOCKER_HOST_ADDRESS=${DOCKER_HOST_ADDRESS:-"host.docker.internal"} || DOCKER_HOST_ADDRESS=${DOCKER_HOST_ADDRESS:-"172.17.0.1"}

ANKA_VIRTUALIZATION_DOWNLOAD_URL="$CLOUDFRONT_URL/$ANKA_VIRTUALIZATION_PACKAGE"
ANKA_VM_USER=${ANKA_VM_USER:-"anka"}
ANKA_VM_PASSWORD=${ANKA_VM_PASSWORD:-"admin"}
ANKA_BASE_VM_TEMPLATE_UUID="${ANKA_BASE_VM_TEMPLATE_UUID:-"c12ccfa5-8757-411e-9505-128190e9854e"}" # Used in cloud_tests

CLOUD_CONTROLLER_ADDRESS=${CLOUD_CONTROLLER_ADDRESS:-"anka.controller"}
CLOUD_REGISTRY_ADDRESS=${CLOUD_REGISTRY_ADDRESS:-"anka.registry"}
CLOUD_ETCD_ADDRESS=${CLOUD_ETCD_ADDRESS:-"anka.etcd"}
CLOUD_CONTROLLER_PORT=${CLOUD_CONTROLLER_PORT:-"8090"}
CLOUD_CONTROLLER_DATA_DIR="/Library/Application Support/Veertu/Anka/anka-controller"
CLOUD_CONTROLLER_LOG_DIR="/Library/Logs/Veertu/AnkaController"

CLOUD_REGISTRY_PORT=${CLOUD_REGISTRY_PORT:-"8089"} # 8089 is the default
CLOUD_REGISTRY_REPO_NAME=${CLOUD_REGISTRY_REPO_NAME:-"local-demo"}
CLOUD_REGISTRY_BASE_PATH="/Library/Application Support/Veertu/Anka/registry"
CLOUD_DOCKER_FOLDER="$(echo $CLOUD_DOCKER_TAR | awk -F'.tar.gz' '{print $1}')"

JENKINS_PORT="${JENKINS_PORT:-"8092"}"
JENKINS_SERVICE_PORT="8080"
JENKINS_DOCKER_CONTAINER_NAME="anka.jenkins"
JENKINS_TAG_VERSION=${JENKINS_TAG_VERSION:-"lts"}
JENKINS_DATA_DIR="$HOME/$JENKINS_DOCKER_CONTAINER_NAME-data"
JENKINS_VM_TEMPLATE_UUID="${JENKINS_VM_TEMPLATE_UUID:-"c0847bc9-5d2d-4dbc-ba6a-240f7ff08032"}" # Used in https://github.com/veertuinc/jenkins-dynamic-label-example

GITLAB_PORT="8093"
GITLAB_DOCKER_CONTAINER_NAME="anka.gitlab"
GITLAB_DOCKER_DATA_DIR="$HOME/$GITLAB_DOCKER_CONTAINER_NAME-data"
GITLAB_ROOT_PASSWORD="rootpassword"
GITLAB_ACCESS_TOKEN="token-string-here123"
GITLAB_EXAMPLE_PROJECT_NAME="gitlab-examples"
GITLAB_ANKA_VM_TEMPLATE_TAG="v1"
GITLAB_RUNNER_PROJECT_RUNNER_NAME="anka-gitlab-runner-project-specific"
GITLAB_RUNNER_SHARED_RUNNER_NAME="anka-gitlab-runner-shared"
GITLAB_RUNNER_LOCATION="/tmp/anka-gitlab-runner"
GITLAB_RUNNER_DESTINATION="/usr/local/bin/"
GITLAB_RUNNER_VM_TEMPLATE_UUID="${GITLAB_RUNNER_VM_TEMPLATE_UUID:-"5d1b40b9-7e68-4807-a290-c59c66e926b4"}" # This is used in CI/CD; change screwdriver runner-setup script if you change the name of the var

PROMETHEUS_PORT="8095"
PROMETHEUS_DOCKER_CONTAINER_NAME="anka.prometheus"
PROMETHEUS_DOCKER_TAG_VERSION=${PROMETHEUS_DOCKER_TAG_VERSION:-"2.21.0"}
PROMETHEUS_DOCKER_DATA_DIR="$HOME/$PROMETHEUS_DOCKER_CONTAINER_NAME-data"
PROMETHEUS_BINARY_NAME="anka-prometheus-exporter"

TEAMCITY_PORT="8094"
TEAMCITY_DOCKER_TAG_VERSION=${TEAMCITY_DOCKER_TAG_VERSION:-"$TEAMCITY_VERSION-linux"}
TEAMCITY_DOCKER_CONTAINER_NAME="anka.teamcity"
TEAMCITY_DOCKER_DATA_DIR="$HOME/$TEAMCITY_DOCKER_CONTAINER_NAME-data"

USE_CERTS=${USE_CERTS:-false}
CERT_DIRECTORY=${CERT_DIRECTORY:-"$HOME/anka-build-cloud-certs"}
[[ "$USE_CERTS" == true ]] && CERTS="--cacert $CERT_DIRECTORY/anka-ca-crt.pem --cert $CERT_DIRECTORY/anka-node-$(hostname)-crt.pem --key $CERT_DIRECTORY/anka-node-$(hostname)-key.pem"

modify_hosts() {
  [[ -z $1 ]] && echo "ARG 1 missing" && exit 1
  if [[ $(uname) == "Darwin" ]]; then
    SED="sudo sed -i ''"
  else
    SED="sudo sed -i"
  fi
  HOSTS_LOCATION="/etc/hosts"
  echo "]] Adding $1 to $HOSTS_LOCATION (requires root)"
  $SED "/$1/d" $HOSTS_LOCATION
  ( echo "127.0.0.1 $1" | sudo tee -a $HOSTS_LOCATION ) &>/dev/null
}

jenkins_obtain_crumb() {
  COOKIEJAR="$(mktemp)"
  CRUMB=$(curl -u "admin: admin" --cookie-jar "$COOKIEJAR" -s "http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")
}

jenkins_plugin_install() {
  PLUGIN_NAME=$(echo $1 | cut -d@ -f1)
  PLUGIN_VERSION=$(echo $1 | cut -d@ -f2)
  jenkins_obtain_crumb
  curl -X POST -H "$CRUMB" --cookie "$COOKIEJAR" -d "<jenkins><install plugin=\"${PLUGIN_NAME}@${PLUGIN_VERSION}\" /></jenkins>" --header 'Content-Type: text/xml' http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT/pluginManager/installNecessaryPlugins
  TRIES=0
  while [[ "$(docker logs --tail 500 $JENKINS_DOCKER_CONTAINER_NAME 2>&1 | grep "INFO: Installation successful: ${PLUGIN_NAME}$")" != "INFO: Installation successful: $PLUGIN_NAME" ]]; do
    echo "Installation of $PLUGIN_NAME plugin still pending..."
    sleep 5
    [[ $TRIES == 150 ]] && echo "Something is wrong with the Jenkins $PLUGIN_NAME installation..." && docker logs --tail 100 $JENKINS_DOCKER_CONTAINER_NAME && exit 1
    TRIES=$(($TRIES + 1))
  done
  true
}

modify_uuid() {
  # Modify UUID (don't use in production; for getting-started demo only)
  [[ -z "$1" ]] && echo "no arguments... Please provide JENKINS_TEMPLATE_NAME as ARG1" && exit 1
  [[ -z "$2" ]] && echo "Please provided the new UUID as ARG2" && exit 2
  JENKINS_TEMPLATE_NAME=$1
  DEST_UUID=$2
  CUR_UUID=$(sudo anka --machine-readable list | jq -r ".body[] | select(.name==\"$JENKINS_TEMPLATE_NAME\") | .uuid")
  if [[ -z "$(sudo anka --machine-readable  registry list | jq ".body[] | select(.id == \"${DEST_UUID}\") | .name")" && "${CUR_UUID}" != "${DEST_UUID}" ]]; then
    sudo mv "$(sudo anka config vm_lib_dir)/$CUR_UUID" "$(sudo anka config vm_lib_dir)/$DEST_UUID"
    sudo sed -i '' "s/$CUR_UUID/$DEST_UUID/" "$(sudo anka config vm_lib_dir)/$DEST_UUID/$CUR_UUID.yaml"
    sudo mv "$(sudo anka config vm_lib_dir)/$DEST_UUID/$CUR_UUID.yaml" "$(sudo anka config vm_lib_dir)/$DEST_UUID/$DEST_UUID.yaml"
  fi
}


execute-docker-compose() {
  PATH="/usr/local/bin:$PATH" # Fix for CI/CD
  if [[ ! -z "$(docker compose --help | grep "Usage:  docker compose \[OPTIONS\] COMMAND")" ]]; then
    docker compose "$@"
  elif [[ ! -z "$(command -v docker-compose)" ]]; then
    docker-compose "$@"
  else
    echo "No docker compose/docker-compose found, please install it!"
    exit 1
  fi
}