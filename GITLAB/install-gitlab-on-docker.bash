#!/bin/bash
set -exo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo "]] Cleaning up the previous GitLab installation"
docker stop $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_SHARED_RUNNER_NAME || true
docker stop $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
docker rm $GITLAB_RUNNER_PROJECT_RUNNER_NAME || true
execute-docker-compose down || true
docker stop $GITLAB_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $GITLAB_DOCKER_CONTAINER_NAME &>/dev/null || true
[[ -d "${GITLAB_DOCKER_DATA_DIR}" ]] && sudo rm -rf "${GITLAB_DOCKER_DATA_DIR}"
rm -rf docker-compose.yml
if [[ $1 != "--uninstall" ]]; then
  EXTERNAL_URL=${EXTERNAL_URL:-"${URL_PROTOCOL}${GITLAB_DOCKER_CONTAINER_NAME}:${GITLAB_PORT}"}
  modify_hosts $GITLAB_DOCKER_CONTAINER_NAME
  echo "]] Starting the GitLab Docker container"
  mkdir -p $GITLAB_DOCKER_DATA_DIR/config
  mkdir -p $GITLAB_DOCKER_DATA_DIR/logs
  mkdir -p $GITLAB_DOCKER_DATA_DIR/data
cat > docker-compose.yml <<BLOCK
version: '3.7'
services:
  $GITLAB_DOCKER_CONTAINER_NAME:
    container_name: $GITLAB_DOCKER_CONTAINER_NAME
    hostname: $GITLAB_DOCKER_CONTAINER_NAME
    platform: "linux/amd64"
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
        external_url "$EXTERNAL_URL"
        nginx['listen_port'] = $GITLAB_PORT
        postgresql['max_files_per_process'] = 25
        gitlab_rails['gitlab_ssh_host'] = "$GITLAB_DOCKER_CONTAINER_NAME"
        gitlab_rails['gitlab_shell_ssh_port'] = 2244
    shm_size: '256m'
BLOCK
# gitlab_rails['signin_enabled'] = false
if [[ "$(uname)" == "Linux" ]]; then
cat >> docker-compose.yml <<BLOCK
    extra_hosts:
      - "host.docker.internal:host-gateway"
BLOCK
fi
  execute-docker-compose up -d
  # Check if it's still starting...
  while [[ ! "$(docker logs --tail 100 $GITLAB_DOCKER_CONTAINER_NAME 2>&1)" =~ '==> /var/log/' ]]; do 
    echo "GitLab still starting (this may take a while)..."
    docker logs --tail 50 $GITLAB_DOCKER_CONTAINER_NAME 2>&1
    sleep 60
  done

  # Set proper root password
  docker exec -i anka.gitlab bash -c "gitlab-rails runner \"user = User.find_by_username('root'); user.password = \\\"${GITLAB_ROOT_PASSWORD}\\\"; user.password_confirmation = \\\"${GITLAB_ROOT_PASSWORD}\\\"; user.save!\""

  # Create project
  ## API auth
  # GITLAB_ACCESS_TOKEN=$(curl -s --request POST --data "grant_type=password&username=root&password=$GITLAB_ROOT_PASSWORD" http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/oauth/token | jq -r '.access_token')
  echo "]] Creating Access token (be patient)"
  docker exec -i anka.gitlab bash -c "gitlab-rails runner \"token = User.find_by_username('root').personal_access_tokens.create(scopes: [:read_user, :read_repository, :api], name: 'Automation token'); token.set_token('${GITLAB_ACCESS_TOKEN}'); token.save!\""
  
  ## Create example project
  echo "]] Importing example project"
  sleep 20
  curl -s --request PUT -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/application/settings?import_sources%5B%5D=gi,github"
  curl -s --request POST -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" "${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects?name=$GITLAB_EXAMPLE_PROJECT_NAME&import_url=https://github.com/veertuinc/$GITLAB_EXAMPLE_PROJECT_NAME.git&auto_devops_enabled=false&shared_runners_enabled=true"
  echo "============================================================================"
  echo "GitLab UI: ${URL_PROTOCOL}$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT"
  echo "Logins: root / $GITLAB_ROOT_PASSWORD"
fi