#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with brew install jq." && exit 1
SOURCE_TEMPLATE=$1
[[ -z $SOURCE_TEMPLATE ]] && echo "No Template Name specified as ARG1..." && exit 1
HELPERS="set -exo pipefail;"
ANKA_RUN="sudo anka run -N -n"
[[ ! -z "$(sudo anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME)" ]] && REMOTE="--remote $CLOUD_REGISTRY_REPO_NAME"
ANKA_REGISTRY="sudo anka registry $REMOTE $CERTS"

cleanup() {
  sudo anka stop --yes $TEMPLATE || true
}
trap cleanup INT

pull() {
  [[ ! -z $1 ]] && TEMPLATE=$1
  [[ ! -z $2 ]] && TAG=$2
  $ANKA_REGISTRY pull $TEMPLATE -t $TAG
}

suspend_and_push() {
  TEMPLATE=$1
  TAG=$2
  echo "]] Suspending VM $TEMPLATE and pushing with tag: $TAG..."
  sudo anka suspend $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

stop_and_push() {
  TEMPLATE=$1
  TAG=$2
  echo "]] Stopping VM $TEMPLATE and pushing with tag: $TAG..."
  sudo anka stop $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG || true
}

does_not_exist() {
  TEMPLATE=$1
  TAG=$2
  [[ -z $(sudo anka --machine-readable registry $REMOTE $CERTS describe $TEMPLATE | jq -r ".body.versions[] | select(.tag == \"$TAG\") | .tag" 2>/dev/null) ]] && true || false
}

prepare-and-push() {
  TEMPLATE="$1"
  TAG="$2"
  echo "]] Preparing and pushing VM template $TEMPLATE and tag $TAG"
  if does_not_exist $TEMPLATE $TAG; then
    eval "$4"
    [[ "$3" == "stop" ]] && stop_and_push $TEMPLATE $TAG || suspend_and_push $TEMPLATE $TAG
  else
    pull $TEMPLATE $TAG
    echo "Already found in registry!"
  fi
}

#############################
# Generate and push base tags
# Tripple quote nested quotes and $
####################################

TAG=${TAG:-"vanilla"}
if does_not_exist $SOURCE_TEMPLATE $TAG; then
  stop_and_push $SOURCE_TEMPLATE $TAG
fi

# Set port-forwarding
prepare-and-push $SOURCE_TEMPLATE "$TAG+port-forward-22" "stop" "
  sudo anka modify $SOURCE_TEMPLATE add port-forwarding --guest-port 22 ssh || true
"
# Install Brew & command line tools (git)
prepare-and-push $SOURCE_TEMPLATE "$TAG+brew-git" "stop" "
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo xcodebuild -license || true\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"/bin/bash -c \\\"\\\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)\\\"\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.coreduetd.osx.plist\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"brew install jq\"
"

if [[ $2 == '--gitlab' ]]; then
  NEW_TEMPLATE="11.2-gitlab"
  NEW_TAG="v1"
  does_not_exist $NEW_TEMPLATE $NEW_TAG && sudo anka clone $SOURCE_TEMPLATE $NEW_TEMPLATE
  # Modify UUID (don't use in production; for getting-started demo only)
  CUR_UUID=$(sudo anka --machine-readable list | jq -r ".body[] | select(.name==\"$NEW_TEMPLATE\") | .uuid")
  sudo mv "$(sudo anka config vm_lib_dir)/$CUR_UUID" "$(sudo anka config vm_lib_dir)/$GITLAB_RUNNER_VM_TEMPLATE_UUID"
  sudo sed -i '' "s/$CUR_UUID/$GITLAB_RUNNER_VM_TEMPLATE_UUID/" "$(sudo anka config vm_lib_dir)/$GITLAB_RUNNER_VM_TEMPLATE_UUID/$CUR_UUID.yaml"
  sudo mv "$(sudo anka config vm_lib_dir)/$GITLAB_RUNNER_VM_TEMPLATE_UUID/$CUR_UUID.yaml" "$(sudo anka config vm_lib_dir)/$GITLAB_RUNNER_VM_TEMPLATE_UUID/$GITLAB_RUNNER_VM_TEMPLATE_UUID.yaml"
  prepare-and-push $NEW_TEMPLATE $NEW_TAG "suspend" "
    $ANKA_RUN $NEW_TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 anka.gitlab' >> /etc/hosts && [[ ! -z \\\$(grep anka.gitlab /etc/hosts) ]]\"
  "
fi

if [[ $2 == '--jenkins' ]] || [[ $2 == '--teamcity' ]]; then
  NEW_TEMPLATE="11.2-openjdk-1.8.0_242"
  NEW_TAG="v1"
  does_not_exist $NEW_TEMPLATE $NEW_TAG && sudo anka clone $SOURCE_TEMPLATE $NEW_TEMPLATE
  ## Install OpenJDK8
  prepare-and-push $NEW_TEMPLATE $NEW_TAG "stop" "
    $ANKA_RUN $NEW_TEMPLATE bash -c \"$HELPERS cd /tmp && rm -f /tmp/OpenJDK* && \
    curl -L -O https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u242-b08/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg && \
    [ \\\$(du -s /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg | awk '{print \\\$1}') -gt 190000 ] && \
    sudo installer -pkg /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg -target / && \
    [[ ! -z \\\$(java -version 2>&1 | grep 1.8.0_242) ]] && \
    rm -f /tmp/OpenJDK8U-jdk_x64_mac_hotspot_8u242b08.pkg\"
  "
fi

if [[ $2 == '--jenkins' ]]; then
  NEW_TAG="v1"
  JENKINS_TEMPLATE="11.2-openjdk-1.8.0_242-jenkins"
  does_not_exist $JENKINS_TEMPLATE $NEW_TAG && sudo anka clone $NEW_TEMPLATE $JENKINS_TEMPLATE
  # Modify UUID (don't use in production; for getting-started demo only)
  CUR_UUID=$(sudo anka --machine-readable list | jq -r ".body[] | select(.name==\"$JENKINS_TEMPLATE\") | .uuid")
  sudo mv "$(sudo anka config vm_lib_dir)/$CUR_UUID" "$(sudo anka config vm_lib_dir)/$JENKINS_VM_TEMPLATE_UUID"
  sudo sed -i '' "s/$CUR_UUID/$JENKINS_VM_TEMPLATE_UUID/" "$(sudo anka config vm_lib_dir)/$JENKINS_VM_TEMPLATE_UUID/$CUR_UUID.yaml"
  sudo mv "$(sudo anka config vm_lib_dir)/$JENKINS_VM_TEMPLATE_UUID/$CUR_UUID.yaml" "$(sudo anka config vm_lib_dir)/$JENKINS_VM_TEMPLATE_UUID/$JENKINS_VM_TEMPLATE_UUID.yaml"
  ## Jenkins misc (Only needed if you're running Jenkins on the same host you run the VMs)
  prepare-and-push $JENKINS_TEMPLATE $NEW_TAG "suspend" "
    $ANKA_RUN $JENKINS_TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 anka.jenkins' >> /etc/hosts && [[ ! -z \\\$(grep anka.jenkins /etc/hosts) ]]\"
  "
fi

if [[ $2 == '--teamcity' ]]; then
  NEW_TAG="v1"
  TEAMCITY_TEMPLATE="11.2-openjdk-1.8.0_242-teamcity"
  does_not_exist $TEAMCITY_TEMPLATE $NEW_TAG && sudo anka clone $NEW_TEMPLATE $TEAMCITY_TEMPLATE
  prepare-and-push $TEAMCITY_TEMPLATE $NEW_TAG "suspend" "
    $ANKA_RUN $TEAMCITY_TEMPLATE sudo bash -c \"$HELPERS echo '192.168.64.1 $TEAMCITY_DOCKER_CONTAINER_NAME' >> /etc/hosts && [[ ! -z \\\$(grep $TEAMCITY_DOCKER_CONTAINER_NAME /etc/hosts) ]]\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"curl -O -L https://download.jetbrains.com/teamcity/TeamCity-$TEAMCITY_VERSION.tar.gz\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"tar -xzvf TeamCity-$TEAMCITY_VERSION.tar.gz && mv Teamcity/BuildAgent /Users/anka/buildAgent\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"echo >> buildAgent/conf/buildagent.properties\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"sh buildAgent/bin/mac.launchd.sh load && sleep 5\"
  "
fi