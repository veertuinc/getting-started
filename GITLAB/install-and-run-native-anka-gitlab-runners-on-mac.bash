#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
[[ -z "$(docker port anka.gitlab)" ]] && echo "You need to first run install-gitlab-on-docker.bash" && exit 1
# Cleanup
echo "]] Cleaning up previous runners..."
anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} stop || true
anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} unregister -n "localhost shared runner" || true
anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} unregister -n "localhost specific runner" || true
sudo anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} uninstall || true
[[ -e $GITLAB_RUNNER_DESTINATION/anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} ]]&& rm -f $GITLAB_RUNNER_DESTINATION/anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}
# Install
if [[ $1 != "--uninstall" ]]; then
  mkdir -p $GITLAB_RUNNER_LOCATION
  pushd $GITLAB_RUNNER_LOCATION &>/dev/null
  modify_hosts $GITLAB_DOCKER_CONTAINER_NAME
  echo "]] Downloading and unpacking tar..."
  curl -s -L -o anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}-darwin-amd64.tar.gz https://github.com/veertuinc/gitlab-runner/releases/download/v${GITLAB_ANKA_RUNNER_VERSION}/anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}-darwin-amd64.tar.gz
  tar -xzvf anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}-darwin-amd64.tar.gz &>/dev/null
  cp -rfp $GITLAB_RUNNER_LOCATION/anka-gitlab-runner-darwin-* $GITLAB_RUNNER_DESTINATION/anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}
  chmod +x $GITLAB_RUNNER_DESTINATION/anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION}
  popd &>/dev/null
  echo "]] Collecting tokens from GitLab..."
  export GITLAB_ACCESS_TOKEN=$(curl -s --request POST --data "grant_type=password&username=root&password=$GITLAB_ROOT_PASSWORD" http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/oauth/token | jq -r '.access_token')
  export GITLAB_EXAMPLE_PROJECT_ID=$(curl -s --request GET -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects" | jq -r ".[] | select(.name==\"$GITLAB_EXAMPLE_PROJECT_NAME\") | .id")
  export SHARED_REGISTRATION_TOKEN="$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token\"")"
  export PROJECT_REGISTRATION_TOKEN=$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Project.find_by_id($GITLAB_EXAMPLE_PROJECT_ID).runners_token\"")
  
  anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} register --non-interactive \
  --url "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/" \
  --registration-token $SHARED_REGISTRATION_TOKEN \
  --ssh-user anka \
  --ssh-password admin \
  --name "localhost shared runner" \
  --anka-controller-address "http://anka.controller:8090/" \
  --anka-template-uuid c0847bc9-5d2d-4dbc-ba6a-240f7ff08032 \
  --anka-tag base:port-forward-22:brew-git:gitlab \
  --executor anka \
  --clone-url "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
  --tag-list "localhost-shared,localhost,iOS"

  anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} register --non-interactive \
  --url "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
  --registration-token $PROJECT_REGISTRATION_TOKEN \
  --ssh-user anka \
  --ssh-password admin \
  --name "localhost specific runner" \
  --anka-controller-address "http://anka.controller:8090/" \
  --anka-template-uuid c0847bc9-5d2d-4dbc-ba6a-240f7ff08032 \
  --anka-tag base:port-forward-22:brew-git:gitlab \
  --executor anka \
  --clone-url "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
  --tag-list "localhost-specific,localhost,iOS"

  sudo anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} install --user $USER --config $HOME/.gitlab-runner/anka-config.toml
  sudo anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} start
  echo "]] Verifying runners"
  anka-gitlab-runner-v${GITLAB_ANKA_RUNNER_VERSION} verify
fi