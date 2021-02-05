[[ $DEBUG == true ]] && set -x

STORAGE_LOCATION=${STORAGE_LOCATION:-"/tmp"}
URL_PROTOCOL=${URL_PROTOCOL:-"http://"}

JENKINS_PLUGIN_VERSION="2.3.0"
JENKINS_PIPELINE_PLUGIN_VERSION="1.7.2"
GITHUB_PLUGIN_VERSION="1.32.0"
GITLAB_ANKA_RUNNER_VERSION=v${GITLAB_ANKA_RUNNER_VERSION:-"1.2.1"}
GITLAB_RELEASE_TYPE=${GITLAB_RELEASE_TYPE:-"ce"}
GITLAB_DOCKER_TAG_VERSION=${GITLAB_DOCKER_TAG_VERSION:-"13.4.1-$GITLAB_RELEASE_TYPE.0"}
CLOUD_NATIVE_PACKAGE=${CLOUD_NATIVE_PACKAGE:-"AnkaControllerRegistry-1.13.0-24e848a5.pkg"}
CLOUD_DOCKER_TAR=${CLOUD_DOCKER_TAR:-"anka-controller-registry-1.13.0-24e848a5.tar.gz"}
ANKA_VIRTUALIZATION_PACKAGE=${ANKA_VIRTUALIZATION_PACKAGE:-"Anka-2.3.3.127.pkg"}
TEAMCITY_VERSION="2020.2.2"

CLOUDFRONT_URL="https://d1efqjhnhbvc57.cloudfront.net"

ANKA_VIRTUALIZATION_DOWNLOAD_URL="$CLOUDFRONT_URL/$ANKA_VIRTUALIZATION_PACKAGE"
ANKA_VM_USER=${ANKA_VM_USER:-"anka"}
ANKA_VM_PASSWORD=${ANKA_VM_PASSWORD:-"admin"}

CLOUD_CONTROLLER_ADDRESS=${CLOUD_CONTROLLER_ADDRESS:-"anka.controller"}
CLOUD_REGISTRY_ADDRESS=${CLOUD_REGISTRY_ADDRESS:-"anka.registry"}
CLOUD_ETCD_ADDRESS=${CLOUD_ETCD_ADDRESS:-"anka.etcd"}
CLOUD_CONTROLLER_PORT="8090"
CLOUD_CONTROLLER_DATA_DIR="/Library/Application Support/Veertu/Anka/anka-controller"
CLOUD_CONTROLLER_LOG_DIR="/Library/Logs/Veertu/AnkaController"

CLOUD_REGISTRY_PORT="8089" # 8089 is the default
CLOUD_REGISTRY_REPO_NAME=${CLOUD_REGISTRY_REPO_NAME:-"local-demo"}
CLOUD_REGISTRY_BASE_PATH="/Library/Application Support/Veertu/Anka/registry"
CLOUD_DOCKER_FOLDER="$(echo $CLOUD_DOCKER_TAR | awk -F'.tar.gz' '{print $1}')"

JENKINS_PORT=8092
JENKINS_SERVICE_PORT="8080"
JENKINS_DOCKER_CONTAINER_NAME="anka.jenkins"
JENKINS_TAG_VERSION=${JENKINS_TAG_VERSION:-"lts"}
JENKINS_DATA_DIR="$HOME/$JENKINS_DOCKER_CONTAINER_NAME-data"
JENKINS_VM_TEMPLATE_UUID="${JENKINS_VM_TEMPLATE_UUID:-"c0847bc9-5d2d-4dbc-ba6a-240f7ff08032"}" # Used in https://github.com/veertuinc/jenkins-dynamic-label-example


GITLAB_PORT="8093"
GITLAB_DOCKER_CONTAINER_NAME="anka.gitlab"
GITLAB_DOCKER_DATA_DIR="$HOME/$GITLAB_DOCKER_CONTAINER_NAME-data"
GITLAB_ROOT_PASSWORD="rootpassword"
GITLAB_EXAMPLE_PROJECT_NAME="gitlab-examples"
GITLAB_ANKA_VM_TEMPLATE_TAG="vanilla:port-forward-22:brew-git:gitlab"
GITLAB_RUNNER_PROJECT_RUNNER_NAME="anka-gitlab-runner-project-specific"
GITLAB_RUNNER_SHARED_RUNNER_NAME="anka-gitlab-runner-shared"
GITLAB_RUNNER_LOCATION="/tmp/anka-gitlab-runner"
GITLAB_RUNNER_DESTINATION="/usr/local/bin/"
GITLAB_RUNNER_VM_TEMPLATE_UUID="${GITLAB_RUNNER_VM_TEMPLATE_UUID:-"5d1b40b9-7e68-4807-a290-c59c66e926b4"}"


TEAMCITY_PORT="8094"
TEAMCITY_DOCKER_TAG_VERSION=${TEAMCITY_DOCKER_TAG_VERSION:-"$TEAMCITY_VERSION-linux"}
TEAMCITY_DOCKER_CONTAINER_NAME="anka.teamcity"
TEAMCITY_DOCKER_DATA_DIR="$HOME/$TEAMCITY_DOCKER_CONTAINER_NAME-data"

CERT_DIRECTORY=${CERT_DIRECTORY:-"$HOME/anka-build-cloud-certs"}

modify_hosts() {
  [[ -z $1 ]] && echo "ARG 1 missing" && exit 1
  if [[ $(uname) == "Darwin" ]]; then
    SED="sudo sed -i ''"
  else
    SED="sudo sed -i"
  fi
  HOSTS_LOCATION="/etc/hosts"
  $SED "/$1/d" $HOSTS_LOCATION
  echo "127.0.0.1 $1" | sudo tee -a $HOSTS_LOCATION
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
    [[ $TRIES == 25 ]] && echo "Something is wrong with the Jenkins $PLUGIN_NAME installation..." && docker logs --tail 50 $JENKINS_DOCKER_CONTAINER_NAME && exit 1
    ((TRIES++))
  done
  true
}