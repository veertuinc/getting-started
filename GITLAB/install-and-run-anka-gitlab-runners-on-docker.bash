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
if [[ $1 == "--https" ]]; then
  VOLUMES="-v $CERT_DIRECTORY:/certs"
  EXTRAS="--anka-root-ca-path /certs/anka-ca-crt.pem --anka-cert-path /certs/anka-gitlab-crt.pem --anka-key-path /certs/anka-gitlab-key.pem"
  URL_PROTOCOL="https://"
fi
if [[ $1 != "--uninstall" ]]; then
  VM_CLONE_ADDRESS="${VM_CLONE_ADDRESS:-"${GITLAB_DOCKER_CONTAINER_NAME}"}"
  ANKA_CONTROLLER_ADDRESS=${ANKA_CONTROLLER_ADDRESS:-"${URL_PROTOCOL}${DOCKER_HOST_ADDRESS}:$CLOUD_CONTROLLER_PORT"}
  GITLAB_EXAMPLE_PROJECT_ID=$(curl -s --request GET -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects" | jq -r ".[] | select(.name==\"$GITLAB_EXAMPLE_PROJECT_NAME\") | .id")
  # GitLab Runner
  DOCKER_RUN_EXTRAS="--rm -ti -d ${VOLUMES} veertu/anka-gitlab-runner-amd64:v${GITLAB_ANKA_RUNNER_VERSION}"
  [[ "$(uname)" == "Linux" ]] && DOCKER_RUN_EXTRAS="--add-host=host.docker.internal:host-gateway ${DOCKER_RUN_EXTRAS}"
  ## Collect the Shared runner token
  SHARED_REGISTRATION_TOKEN="${SHARED_REGISTRATION_TOKEN:-"$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Gitlab::CurrentSettings.current_application_settings.runners_registration_token\"")"}"
  echo "]] Starting a shared Anka GitLab Runner (Docker container: $GITLAB_RUNNER_SHARED_RUNNER_NAME) and connecting it to your GitLab"
  docker run --name $GITLAB_RUNNER_SHARED_RUNNER_NAME ${DOCKER_RUN_EXTRAS} \
  --url "http://${DOCKER_HOST_ADDRESS}:$GITLAB_PORT" \
  --registration-token $SHARED_REGISTRATION_TOKEN \
  --ssh-user $ANKA_VM_USER \
  --ssh-password $ANKA_VM_PASSWORD \
  --name "localhost shared runner" \
  --anka-controller-address $ANKA_CONTROLLER_ADDRESS \
  --anka-template-uuid $GITLAB_RUNNER_VM_TEMPLATE_UUID_INTEL \
  --anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
  --executor anka \
  $EXTRAS \
  --clone-url "http://${VM_CLONE_ADDRESS}:${GITLAB_PORT}" \
  --tag-list "localhost-shared,localhost,iOS"
  ## Collect the project runner token
  PROJECT_REGISTRATION_TOKEN=${PROJECT_REGISTRATION_TOKEN:-"$(docker exec -i $GITLAB_DOCKER_CONTAINER_NAME bash -c "gitlab-rails runner -e production \"puts Project.find_by_id($GITLAB_EXAMPLE_PROJECT_ID).runners_token\"")"}
  echo "]] Starting a project specific Anka GitLab Runner (Docker container: $GITLAB_RUNNER_PROJECT_RUNNER_NAME) and connecting it to your GitLab"
  docker run --name $GITLAB_RUNNER_PROJECT_RUNNER_NAME ${DOCKER_RUN_EXTRAS} \
  --url "http://${DOCKER_HOST_ADDRESS}:$GITLAB_PORT" \
  --registration-token $PROJECT_REGISTRATION_TOKEN \
  --ssh-user $ANKA_VM_USER \
  --ssh-password $ANKA_VM_PASSWORD \
  --name "localhost project specific runner" \
  --anka-controller-address $ANKA_CONTROLLER_ADDRESS \
  --anka-template-uuid $GITLAB_RUNNER_VM_TEMPLATE_UUID_INTEL \
  --anka-tag $GITLAB_ANKA_VM_TEMPLATE_TAG \
  --executor anka \
  $EXTRAS \
  --clone-url "http://${VM_CLONE_ADDRESS}:${GITLAB_PORT}" \
  --tag-list "localhost-specific,localhost,iOS"
fi