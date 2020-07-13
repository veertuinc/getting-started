[[ $DEBUG == true ]] && set -x

STORAGE_LOCATION=${STORAGE_LOCATION:-"/tmp"}
URL_PROTOCOL="http://"

ANKA_PLUGIN_VERSION="2.1.2"
GITHUB_PLUGIN_VERSION="1.30.0"
PIPELINE_PLUGIN_VERSION="1.7.0"

ANKA_VIRTUALIZATION_PACKAGE=${ANKA_VIRTUALIZATION_PACKAGE:-"Anka-2.2.3.118.pkg"}
ANKA_VIRTUALIZATION_DOWNLOAD_URL="https://d1efqjhnhbvc57.cloudfront.net/$ANKA_VIRTUALIZATION_PACKAGE"
ANKA_VM_USER=${ANKA_VM_USER:-"anka"}
ANKA_VM_PASSWORD=${ANKA_VM_PASSWORD:-"admin"}
ANKA_VM_TEMPLATE_UUID="c0847bc9-5d2d-4dbc-ba6a-240f7ff08032" # Used in https://github.com/veertuinc/jenkins-dynamic-label-example

CLOUD_CONTROLLER_ADDRESS=${CLOUD_CONTROLLER_ADDRESS:-"anka.controller"}
CLOUD_REGISTRY_ADDRESS=${CLOUD_REGISTRY_ADDRESS:-"anka.registry"}
CLOUD_CONTROLLER_PORT="8090"
CLOUD_CONTROLLER_DATA_DIR="/Library/Application Support/Veertu/Anka/anka-controller"
CLOUD_CONTROLLER_LOG_DIR="/Library/Logs/Veertu/AnkaController"

CLOUD_REGISTRY_PORT="8091"
CLOUD_REGISTRY_REPO_NAME="local-demo"
CLOUD_REGISTRY_BASE_PATH="/Library/Application Support/Veertu/Anka/registry"
CLOUD_NATIVE_PACKAGE=${CLOUD_NATIVE_PACKAGE:-"AnkaControllerRegistry-1.9.0-4a9f310f.pkg"}
CLOUD_DOCKER_TAR="anka-controller-registry-1.9.0-4a9f310f.tar.gz"
CLOUD_DOCKER=$(echo $CLOUD_DOCKER_TAR | awk -F'.tar.gz' '{print $1}')
CLOUD_DOWNLOAD_URL="https://d1efqjhnhbvc57.cloudfront.net/$CLOUD_NATIVE_PACKAGE"

JENKINS_PORT=8092
JENKINS_SERVICE_PORT="8080"
JENKINS_DOCKER_CONTAINER_NAME="anka.jenkins"
JENKINS_TAG_VERSION=${JENKINS_TAG_VERSION:-"lts"}
JENKINS_DATA_DIR="$HOME/$JENKINS_DOCKER_CONTAINER_NAME-data"

GITLAB_PORT="8093"
GITLAB_RELEASE_TYPE=${GITLAB_RELEASE_TYPE:-"ce"}
GITLAB_DOCKER_CONTAINER_NAME="anka.gitlab"
GITLAB_DOCKER_TAG_VERSION="12.10.1-$GITLAB_RELEASE_TYPE.0"
GITLAB_DOCKER_DATA_DIR="$HOME/$GITLAB_DOCKER_CONTAINER_NAME-data"
GITLAB_ROOT_PASSWORD="adminpassword"
GITLAB_EXAMPLE_PROJECT_NAME="gitlab-examples"
GITLAB_ANKA_VM_TEMPLATE_TAG="base:port-forward-22:brew-git:gitlab"
GITLAB_RUNNER_PROJECT_RUNNER_NAME="anka-gitlab-runner-project-specific"
GITLAB_RUNNER_SHARED_RUNNER_NAME="anka-gitlab-runner-shared"
GITLAB_ANKA_RUNNER_VERSION=${GITLAB_ANKA_RUNNER_VERSION:-"1.0"}
GITLAB_RUNNER_LOCATION="/tmp/anka-gitlab-runner"
GITLAB_RUNNER_DESTINATION="/usr/local/bin/"
GITLAB_RUNNER_LOCATION="/tmp/anka-gitlab-runner"
GITLAB_RUNNER_DESTINATION="/usr/local/bin/"

TEAMCITY_PORT="8094"
TEAMCITY_VERSION="2020.1.1"
TEAMCITY_DOCKER_TAG_VERSION=${TEAMCITY_DOCKER_TAG_VERSION:-"$TEAMCITY_VERSION-linux"}
TEAMCITY_DOCKER_CONTAINER_NAME="anka.teamcity"
TEAMCITY_DOCKER_DATA_DIR="$HOME/$TEAMCITY_DOCKER_CONTAINER_NAME-data"

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
    [[ $TRIES == 25 ]] && echo "Something is wrong with the Jenkins $PLUGIN_NAME installation..." && docker logs --tail 10 $JENKINS_DOCKER_CONTAINER_NAME && exit 1
    ((TRIES++))
  done
  true
}