#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo "]] Cleaning up the previous GitLab installation"
docker stop $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker stop $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
docker-compose down || true
docker stop $GITLAB_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $GITLAB_DOCKER_CONTAINER_NAME &>/dev/null || true
rm -rf $GITLAB_DOCKER_DATA_DIR
rm -rf docker-compose.yml
if [[ $1 != "--uninstall" ]]; then
  modify_hosts $GITLAB_DOCKER_CONTAINER_NAME
  echo "]] Starting the GitLab Docker container"
cat > docker-compose.yml <<BLOCK
version: '3.7'
services:
  $GITLAB_DOCKER_CONTAINER_NAME:
    container_name: $GITLAB_DOCKER_CONTAINER_NAME
    image: gitlab/gitlab-$GITLAB_RELEASE_TYPE:$GITLAB_DOCKER_TAG_VERSION
    restart: always
    ports:
      - "$GITLAB_PORT:$GITLAB_PORT"
      - "2244:22"
    volumes:
      - $GITLAB_DOCKER_DATA_DIR/config:/etc/gitlab
      - $GITLAB_DOCKER_DATA_DIR/logs:/var/log/gitlab
      - $GITLAB_DOCKER_DATA_DIR/data:/var/opt/gitlab
    environment:
      GITLAB_OMNIBUS_CONFIG: |
          external_url '${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT'
          nginx['listen_port'] = $GITLAB_PORT
          gitlab_rails['gitlab_ssh_host'] = '$GITLAB_DOCKER_CONTAINER_NAME'
          gitlab_rails['gitlab_shell_ssh_port'] = 2244
          gitlab_rails['initial_root_password'] = "$GITLAB_ROOT_PASSWORD"
          gitlab_rails['signin_enabled'] = false
BLOCK
  docker-compose up -d
  # Check if it's still starting...
  while [[ ! "$(docker logs --tail 100 $GITLAB_DOCKER_CONTAINER_NAME 2>&1)" =~ '==> /var/log/' ]]; do 
    echo "GitLab still starting..."
    docker logs --tail 50 $GITLAB_DOCKER_CONTAINER_NAME 2>&1
    sleep 60
  done
  # Create project
  ## API auth
  GITLAB_ACCESS_TOKEN=$(curl -s --request POST --data "grant_type=password&username=root&password=$GITLAB_ROOT_PASSWORD" http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/oauth/token | jq -r '.access_token')
  ## Create example project
  echo "]] Importing example project"
  curl --request POST -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects?name=$GITLAB_EXAMPLE_PROJECT_NAME&import_url=https://github.com/veertuinc/$GITLAB_EXAMPLE_PROJECT_NAME.git&auto_devops_enabled=false&shared_runners_enabled=true" 1>/dev/null
  echo
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
  echo "============================================================================"
  echo "GitLab UI: ${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT"
  echo "Logins: root / $GITLAB_ROOT_PASSWORD"
fi