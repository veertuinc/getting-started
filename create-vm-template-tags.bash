#!/bin/bash
set -exo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$SCRIPT_DIR"
. ./shared.bash
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with brew install jq." && exit 1
[[ -z "${1}" ]] && echo "you must provide the source template NAME (not UUID) as the first ARG..." && exit 2
SOURCE_TEMPLATE="${1}"
[[ -z $SOURCE_TEMPLATE ]] && echo "No Template Name specified as ARG1..." && exit 1
HELPERS="set -exo pipefail;PATH=\\\$PATH:/usr/local/bin:/opt/homebrew/bin;"
ANKA_RUN="${SUDO} anka ${ANKA_DEBUG} run -N -n"
[[ ! -z "$(${SUDO} anka registry list-repos | grep $CLOUD_REGISTRY_REPO_NAME)" ]] && REMOTE="--remote $CLOUD_REGISTRY_REPO_NAME"
ANKA_REGISTRY="time ${SUDO} anka ${ANKA_DEBUG} registry $REMOTE $CERTS"

cleanup() {
  ${SUDO} anka stop -f $TEMPLATE || true
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
  ${SUDO} anka suspend $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG -f || true
}

stop_and_push() {
  TEMPLATE=$1
  TAG=$2
  echo "]] Stopping VM $TEMPLATE and pushing with tag: $TAG..."
  ${SUDO} anka stop $TEMPLATE || true
  $ANKA_REGISTRY push $TEMPLATE $TAG -f || true
}

does_not_exist() {
  TEMPLATE=$1
  TAG=$2
  if [[ $(${SUDO} anka --machine-readable registry $REMOTE $CERTS describe $TEMPLATE | jq  -r '.status') != "ERROR" ]]; then
    [[ -z $(${SUDO} anka --machine-readable registry $REMOTE $CERTS describe $TEMPLATE | jq -r ".body.versions[] | select(.tag == \"$TAG\") | .tag" 2>/dev/null) ]] && true || false
  fi
}

prepare-and-push() {
  TEMPLATE="$1"
  TAG="$2"
  echo "]] Preparing and pushing VM template $TEMPLATE and tag $TAG"
  if does_not_exist "$TEMPLATE" "$TAG"; then
    eval "$4"
    if [[ "$3" == "stop" ]]; then
      stop_and_push "$TEMPLATE" "$TAG"
    else
      suspend_and_push "$TEMPLATE" "$TAG"
    fi
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
  ${SUDO} anka modify $SOURCE_TEMPLATE add port-forwarding --guest-port 22 ssh || true
"
# Install Brew & command line tools (git)
prepare-and-push $SOURCE_TEMPLATE "$TAG+brew-git" "stop" "
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo /usr/sbin/DevToolsSecurity --enable\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"defaults write NSGlobalDomain NSAppSleepDisabled -bool YES\" # Disable App Nap System Wide
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo defaults write /Library/Preferences/com.apple.keyboardtype "keyboardtype" -dict-add "3-7582-0" -int 40\" # Disable Keyboard Setup Assistant window
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo pmset hibernatemode 0; sudo rm -f /var/vm/sleepimage\" # Turn off hibernation and get rid of the sleepimage
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo xcodebuild -license || true\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"/bin/bash -c \\\"\\\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)\\\"\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"[[ -f /opt/homebrew/bin/brew ]] && echo \\\"eval \\\"\\\$(/opt/homebrew/bin/brew shellenv)\\\"\\\" >> /Users/anka/.zprofile || true\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.coreduetd.osx.plist\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"launchctl unload -w /System/Library/LaunchAgents/com.apple.wifi.WiFiAgent.plist || true\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sleep 40; pkill \\\"Feedback Assistant\\\" || true\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array \\\"/Volumes\\\"; \
    sudo defaults write ~/.Spotlight-V100/VolumeConfiguration.plist Exclusions -array \\\"/Network\\\"; \
    sudo killall mds; \
    sleep 60; \
    sudo mdutil -a -i off /; \
    sudo mdutil -a -i off; \
    sudo launchctl unload -w /System/Library/LaunchDaemons/com.apple.metadata.mds.plist; \
    sudo rm -rf /.Spotlight-V100/*\"
  $ANKA_RUN $SOURCE_TEMPLATE bash -c \"PATH=\\\"\\\$PATH:/opt/homebrew/bin\\\" brew install jq\"
"

if [[ $2 == '--github-actions' ]]; then
  NEW_TEMPLATE="$SOURCE_TEMPLATE-github-actions"
  NEW_TAG="${GITHUB_ACTIONS_ANKA_VM_TEMPLATE_TAG}"
  does_not_exist $NEW_TEMPLATE $NEW_TAG && ${SUDO} anka clone $SOURCE_TEMPLATE $NEW_TEMPLATE && modify_uuid $NEW_TEMPLATE $GITHUB_ACTIONS_VM_TEMPLATE_UUID
  prepare-and-push $NEW_TEMPLATE $NEW_TAG "stop" "
    $ANKA_RUN $NEW_TEMPLATE bash -c \"\$(curl -sS https://raw.githubusercontent.com/veertuinc/getting-started/master/GITHUB_ACTIONS/install.sh)\"
  "
fi

if [[ $2 == '--gitlab' ]]; then
  NEW_TEMPLATE="$SOURCE_TEMPLATE-gitlab"
  NEW_TAG="${GITLAB_ANKA_VM_TEMPLATE_TAG}"
  does_not_exist $NEW_TEMPLATE $NEW_TAG && ${SUDO} anka clone $SOURCE_TEMPLATE $NEW_TEMPLATE && modify_uuid $NEW_TEMPLATE $GITLAB_VM_TEMPLATE_UUID
  prepare-and-push $NEW_TEMPLATE $NEW_TAG "suspend" "
    $ANKA_RUN $NEW_TEMPLATE sudo bash -c \"$HELPERS echo \$(sudo defaults read /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist Shared_Net_Address) anka.gitlab >> /etc/hosts && cat /etc/hosts && [[ ! -z \\\$(grep anka.gitlab /etc/hosts) ]]\"
  "
  prepare-and-push $NEW_TEMPLATE "v1-with-file" "suspend" "
    $ANKA_RUN $NEW_TEMPLATE bash -c \"$HELPERS touch /Users/anka/Desktop/test.file\"
  "
  # prepare-and-push $NEW_TEMPLATE "v1-no-ssh" "stop" "
  #   $ANKA_RUN $NEW_TEMPLATE bash -c \"$HELPERS sudo rm -f /Library/LaunchDaemons/com.veertu.anka.addons.ssh.plist; sudo launchctl unload -w /System/Library/LaunchDaemons/ssh.plist; launchctl unload -w /System/Library/LaunchDaemons/ssh.plist\"
  # "
fi

if [[ $2 == '--jenkins' ]] || [[ $2 == '--teamcity' ]]; then
  NEW_TEMPLATE="$SOURCE_TEMPLATE-openjdk-11.0.14.1"
  NEW_TAG="v1"
  does_not_exist $NEW_TEMPLATE $NEW_TAG && ${SUDO} anka clone $SOURCE_TEMPLATE $NEW_TEMPLATE
  ## Install OpenJDK
  prepare-and-push $NEW_TEMPLATE $NEW_TAG "stop" "
    $ANKA_RUN $NEW_TEMPLATE bash -c \"$HELPERS \
      [[ \\\$(arch) == arm64 ]] && export ARCH=aarch64 || export ARCH=x64;
      rm -rf zulu*; \
      curl -v -L -O https://cdn.azul.com/zulu/bin/zulu11.54.25-ca-fx-jdk11.0.14.1-macosx_\\\${ARCH}.tar.gz && \
      [ \\\$(du -s zulu11.54.25-ca-fx-jdk11.0.14.1-macosx_\\\${ARCH}.tar.gz  | awk '{print \\\$1}') -gt 190000 ] && \
      tar -xzvf zulu11.54.25-ca-fx-jdk11.0.14.1-macosx_\\\${ARCH}.tar.gz && \
      sudo mkdir -p /usr/local/bin && for file in \\\$(ls ~/zulu11.54.25-ca-fx-jdk11.0.14.1-macosx_\\\${ARCH}/bin/*); do sudo rm -f /usr/local/bin/\\\$(echo \\\$file | rev | cut -d/ -f1 | rev); sudo ln -s \\\$file /usr/local/bin/\\\$(echo \\\$file | rev | cut -d/ -f1 | rev); done && \
      java -version && [[ ! -z \\\$(java -version 2>&1 | grep 11.0.14.1) ]]\"
  "
fi

if [[ $2 == '--jenkins' ]]; then
  NEW_TAG="v1"
  JENKINS_TEMPLATE_NAME="$SOURCE_TEMPLATE-openjdk-11.0.14.1-jenkins"
  does_not_exist $JENKINS_TEMPLATE_NAME $NEW_TAG && ${SUDO} anka clone $NEW_TEMPLATE $JENKINS_TEMPLATE_NAME && modify_uuid $JENKINS_TEMPLATE_NAME $JENKINS_VM_TEMPLATE_UUID
  ## Jenkins misc (Only needed if you're running Jenkins on the same host you run the VMs)
  prepare-and-push $JENKINS_TEMPLATE_NAME $NEW_TAG "stop" "
    $ANKA_RUN $JENKINS_TEMPLATE_NAME sudo bash -c \"$HELPERS echo \$(sudo defaults read /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist Shared_Net_Address) anka.jenkins >> /etc/hosts && cat /etc/hosts && [[ ! -z \\\$(grep anka.jenkins /etc/hosts) ]]\"
  "
fi

if [[ $2 == '--teamcity' ]]; then
  NEW_TAG="v1"
  TEAMCITY_TEMPLATE="$SOURCE_TEMPLATE-openjdk-11.0.14.1-teamcity"
  does_not_exist $TEAMCITY_TEMPLATE $NEW_TAG && ${SUDO} anka clone $NEW_TEMPLATE $TEAMCITY_TEMPLATE
  prepare-and-push $TEAMCITY_TEMPLATE $NEW_TAG "suspend" "
    $ANKA_RUN $TEAMCITY_TEMPLATE sudo bash -c \"$HELPERS echo \$(sudo defaults read /Library/Preferences/SystemConfiguration/com.apple.vmnet.plist Shared_Net_Address) $TEAMCITY_DOCKER_CONTAINER_NAME >> /etc/hosts && cat /etc/hosts && [[ ! -z \\\$(grep $TEAMCITY_DOCKER_CONTAINER_NAME /etc/hosts) ]]\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"curl -O -L https://download.jetbrains.com/teamcity/TeamCity-$TEAMCITY_VERSION.tar.gz\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"tar -xzvf TeamCity-$TEAMCITY_VERSION.tar.gz && mv Teamcity/BuildAgent /Users/anka/buildAgent\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"echo >> buildAgent/conf/buildagent.properties\"
    $ANKA_RUN $TEAMCITY_TEMPLATE bash -c \"sh buildAgent/bin/mac.launchd.sh load && sleep 5\"
  "
fi
echo ""
echo "============================="
echo "Be sure to delete all VMs from the normal user (anka delete --yes --all) as the Controller will pull and start VMs under sudo/root. Otherwise, you'll be using double the disk space."
echo ""