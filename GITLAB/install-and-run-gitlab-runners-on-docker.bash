#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo
docker stop $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker stop $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
if [[ $1 != "--uninstall" ]]; then
  GITLAB_ACCESS_TOKEN=$(curl -s --request POST --data "grant_type=password&username=root&password=$GITLAB_ROOT_PASSWORD" http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/oauth/token | jq -r '.access_token')
  GITLAB_EXAMPLE_PROJECT_ID=$(curl -s --request GET -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects" | jq -r ".[] | select(.name==\"$GITLAB_EXAMPLE_PROJECT_NAME\") | .id")
  # GitLab Runner
  ## Collect the Shared runner token
  SHARED_REGISTRATION_TOKEN="$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token\"")"
  echo "]] Starting a shared Anka GitLab Runner (Docker container: $GITLAB_RUNNER_SHARED_RUNNER_NAME) and connecting it to your GitLab"
  docker run --name $GITLAB_RUNNER_SHARED_RUNNER_NAME -ti -d veertu/anka-gitlab-runner-amd64 \
  --url "${URL_PROTOCOL}host.docker.internal:$GITLAB_PORT" \
  --registration-token $SHARED_REGISTRATION_TOKEN \
  --ssh-user $ANKA_VM_USER \
  --ssh-password $ANKA_VM_PASSWORD \
  --name "localhost shared runner" \
  --anka-controller-address "${URL_PROTOCOL}host.docker.internal:$CLOUD_CONTROLLER_PORT" \
  --anka-template-uuid $ANKA_VM_TEMPLATE_UUID \
  --anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
  --executor anka \
  --clone-url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
  --tag-list "localhost-shared,localhost,iOS"
  ## Collect the project runner token
  PROJECT_REGISTRATION_TOKEN=$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Project.find_by_id($GITLAB_EXAMPLE_PROJECT_ID).runners_token\"")
  echo "]] Starting a shared Anka GitLab Runner (Docker container: $GITLAB_RUNNER_PROJECT_RUNNER_NAME) and connecting it to your GitLab"
  docker run --name $GITLAB_RUNNER_PROJECT_RUNNER_NAME -ti -d veertu/anka-gitlab-runner-amd64 \
  --url "${URL_PROTOCOL}host.docker.internal:$GITLAB_PORT" \
  --registration-token $PROJECT_REGISTRATION_TOKEN \
  --ssh-user $ANKA_VM_USER \
  --ssh-password $ANKA_VM_PASSWORD \
  --name "localhost project specific runner" \
  --anka-controller-address "${URL_PROTOCOL}host.docker.internal:$CLOUD_CONTROLLER_PORT" \
  --anka-template-uuid $ANKA_VM_TEMPLATE_UUID \
  --anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
  --executor anka \
  --clone-url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
  --tag-list "localhost-specific,localhost,iOS"
fi