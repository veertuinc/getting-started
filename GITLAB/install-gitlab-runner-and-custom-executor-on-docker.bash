#!/bin/bash
set -exo pipefail
[[ -z $(command -v jq) ]] && echo "JQ is required. You can install it with brew install jq." && exit 1
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
echo
(
  echo "] ======================================================"
  echo "] Attempting cleaning of older containers, if running..."
  if [[ -f gitlab-runner-auth-token ]]; then
    docker run --rm -v "${SCRIPT_DIR}/config:/etc/gitlab-runner" -ti ${GITLAB_RUNNER_DOCKER_IMAGE} unregister \
      --url "http://${DOCKER_HOST_ADDRESS}:$GITLAB_PORT" --token "$(cat gitlab-runner-auth-token)";
    RUNNER_ID="$(curl -s --header "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" http://anka.gitlab:8093/api/v4/runners/all | jq -r '.[] | select(.description=="gitlab-runner-shared") | .id')"
    curl -s --request DELETE -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/runners/${RUNNER_ID}"
  fi
  docker stop $GITLAB_RUNNER_SHARED_RUNNER_NAME;
  docker rm $GITLAB_RUNNER_SHARED_RUNNER_NAME;
  rm -f gitlab-runner-auth-token
  rm -rf config
) || true
if [[ $1 != "--uninstall" ]]; then
  VM_CLONE_ADDRESS="${VM_CLONE_ADDRESS:-"${GITLAB_DOCKER_CONTAINER_NAME}"}"
  ANKA_CONTROLLER_ADDRESS=${ANKA_CONTROLLER_ADDRESS:-"${URL_PROTOCOL}${DOCKER_HOST_ADDRESS}:$CLOUD_CONTROLLER_PORT"}
  GITLAB_EXAMPLE_PROJECT_ID=$(curl -s --request GET -H "PRIVATE-TOKEN: $GITLAB_ACCESS_TOKEN" "http://$GITLAB_DOCKER_CONTAINER_NAME:$GITLAB_PORT/api/v4/projects" | jq -r ".[] | select(.name==\"$GITLAB_EXAMPLE_PROJECT_NAME\") | .id")
  # GitLab Runner
  [[ "$(uname)" == "Linux" ]] && DOCKER_RUN_EXTRAS="--add-host=host.docker.internal:host-gateway ${DOCKER_RUN_EXTRAS}"
  # download the custom executor
  # curl -LO https://github.com/veertuinc/anka-cloud-gitlab-executor/releases/download/v${GITLAB_RUNNER_CUSTOM_EXECUTOR_VERSION}/${GITLAB_RUNNER_CUSTOM_EXECUTOR_FILE_NAME}

cat > custom-executor.template.toml <<BLOCK
[[runners]]
  [runners.custom]
    config_exec = "/mnt/${GITLAB_RUNNER_CUSTOM_EXECUTOR_FILE_NAME}"
    config_args = ["config"]
    prepare_exec = "/mnt/${GITLAB_RUNNER_CUSTOM_EXECUTOR_FILE_NAME}"
    prepare_args = ["prepare"]
    run_exec = "/mnt/${GITLAB_RUNNER_CUSTOM_EXECUTOR_FILE_NAME}"
    run_args = ["run"]
    cleanup_exec = "/mnt/${GITLAB_RUNNER_CUSTOM_EXECUTOR_FILE_NAME}"
    cleanup_args = ["cleanup"]
BLOCK
  
  ## Collect the Shared runner token
  if [[ ! -f gitlab-runner-auth-token ]]; then
    curl -s -X POST --header "PRIVATE-TOKEN: token-string-here123" --data "runner_type=instance_type&description=${GITLAB_RUNNER_SHARED_RUNNER_NAME}&tag_list=localhost-shared,localhost,iOS" http://anka.gitlab:8093/api/v4/user/runners | cut -d\" -f6 > gitlab-runner-auth-token
  fi
  GITLAB_RUNNER_AUTH_TOKEN="$(cat gitlab-runner-auth-token)"

  # register runner
  docker run --rm -ti \
    -v "${SCRIPT_DIR}:/mnt" -v "${SCRIPT_DIR}/config:/etc/gitlab-runner" ${GITLAB_RUNNER_DOCKER_IMAGE} register \
    --template-config /mnt/custom-executor.template.toml \
    --name "${GITLAB_RUNNER_SHARED_RUNNER_NAME}" \
    --non-interactive \
    --url "http://${DOCKER_HOST_ADDRESS}:$GITLAB_PORT"  \
    --token "${GITLAB_RUNNER_AUTH_TOKEN}" \
    --executor "custom" \
    --clone-url "http://${VM_CLONE_ADDRESS}:${GITLAB_PORT}"

  [[ $(uname) == "Darwin" ]] && SED="sed -i ''" || SED="sed -i"
  
  eval "${SED} '/concurrent.*/c\\
  concurrent = 2\\
  log_level = \"debug\"\\
  log_format = \"text\"\\
' config/config.toml"
  eval "${SED} 's/concurrent.*/concurrent = 2/' config/config.toml"

  eval "${SED} '/executor = \"custom\"/c\\
  executor = \"custom\"\\
  environment = [\\
    \"ANKA_CLOUD_CONTROLLER_URL=http://host.docker.internal:8090\",#\"ANKA_CLOUD_DEBUG=true\",\\
  ]\\
' config/config.toml"

  # Actually run it in the background
  docker run --rm -tid --name "${GITLAB_RUNNER_SHARED_RUNNER_NAME}" \
    -v "${SCRIPT_DIR}:/mnt" -v "${SCRIPT_DIR}/config:/etc/gitlab-runner" ${GITLAB_RUNNER_DOCKER_IMAGE}
fi