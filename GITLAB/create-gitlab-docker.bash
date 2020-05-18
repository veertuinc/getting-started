#!/bin/bash
set -exo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
docker-compose down || true
modify_hosts $GITLAB_DOCKER_CONTAINER_NAME
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
while [[ "$(docker logs --tail 100 $GITLAB_DOCKER_CONTAINER_NAME 2>&1)" =~ 'Running handlers complete' ]]; do 
  echo "GitLab still starting..."
  docker logs --tail 5 $GITLAB_DOCKER_CONTAINER_NAME 2>&1
  sleep 5
done
# Create project
## API auth
GITLAB_ACCESS_TOKEN=$(curl -s --request POST --data "grant_type=password&username=root&password=$GITLAB_ROOT_PASSWORD" http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/oauth/token | jq -r '.access_token')
## Create example project
GITLAB_EXAMPLE_PROJECT_ID=$(curl -s --request GET -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects" | jq -r ".[] | select(.name==\"$GITLAB_EXAMPLE_PROJECT_NAME\") | .id")
curl -s --request DELETE -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects/$GITLAB_EXAMPLE_PROJECT_ID"
curl --request POST -H "Authorization: Bearer $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects?name=$GITLAB_EXAMPLE_PROJECT_NAME&import_url=https://github.com/veertuinc/$GITLAB_EXAMPLE_PROJECT_NAME.git&auto_devops_enabled=false&shared_runners_enabled=true"
# GitLab Runner
## Collect the Shared runner token
SHARED_REGISTRATION_TOKEN=$(docker exec -ti $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token\"")
echo "Registering Shared runner with token: $SHARED_REGISTRATION_TOKEN"
docker stop anka-gitlab-runner-shared
docker rm anka-gitlab-runner-shared
docker run --name anka-gitlab-runner-shared -ti -d veertu/anka-gitlab-runner-amd64 \
--url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
--registration-token $SHARED_REGISTRATION_TOKEN \
--ssh-user $ANKA_VM_USER \
--ssh-password $ANKA_VM_PASSWORD \
--name "localhost shared runner" \
--anka-controller-address "${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT" \
--anka-template-uuid $ANKA_VM_TEMPLATE_UUID \
--anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
--executor anka \
--clone-url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
--tag-list "localhost-shared,localhost,iOS"
## Collect the project runner token
PROJECT_REGISTRATION_TOKEN=$(docker exec -ti $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Project.find_by_id($GITLAB_EXAMPLE_PROJECT_ID).runners_token\"")
echo "Registering Project runner with token: $PROJECT_REGISTRATION_TOKEN"
docker stop anka-gitlab-runner-project-specific
docker rm anka-gitlab-runner-project-specific
docker run --name anka-gitlab-runner-project-specific -ti -d veertu/anka-gitlab-runner-amd64 \
--url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
--registration-token $SHARED_REGISTRATION_TOKEN \
--ssh-user $ANKA_VM_USER \
--ssh-password $ANKA_VM_PASSWORD \
--name "localhost project specific runner" \
--anka-controller-address "${URL_PROTOCOL}$CLOUD_CONTROLLER_ADDRESS:$CLOUD_CONTROLLER_PORT" \
--anka-template-uuid $ANKA_VM_TEMPLATE_UUID \
--anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
--executor anka \
--clone-url "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT" \
--tag-list "localhost-specific,localhost,iOS"
