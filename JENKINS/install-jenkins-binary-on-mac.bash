#!/bin/bash
set -exo pipefail

SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash

SERVICE_PORT="8080"
JENKINS_BINARY_STATE_DIR="${JENKINS_BINARY_STATE_DIR:-$HOME/$JENKINS_DOCKER_CONTAINER_NAME-binary-state}"
JENKINS_BINARY_PID_FILE="$JENKINS_BINARY_STATE_DIR/jenkins.pid"
JENKINS_BINARY_LOG_FILE="$JENKINS_BINARY_STATE_DIR/jenkins.log"
JENKINS_BINARY_WAR_FILE="${JENKINS_BINARY_WAR_FILE:-$JENKINS_BINARY_STATE_DIR/jenkins.war}"
JENKINS_BINARY_MAX_PLUGIN_WAIT_ATTEMPTS="${JENKINS_BINARY_MAX_PLUGIN_WAIT_ATTEMPTS:-90}"
JENKINS_BINARY_WAR_DOWNLOAD_URL="${JENKINS_BINARY_WAR_DOWNLOAD_URL:-https://get.jenkins.io/war-stable/latest/jenkins.war}"
JENKINS_ANKA_MGMT_HOST_FOR_BINARY="${JENKINS_ANKA_MGMT_HOST_FOR_BINARY:-127.0.0.1}"
JENKINS_ANKA_MGMT_PORT_FOR_BINARY="${JENKINS_ANKA_MGMT_PORT_FOR_BINARY:-$CLOUD_CONTROLLER_PORT}"
JENKINS_BINARY_ACTION="${1:-install}"

wait_for_jenkins_http() {
  local jenkins_ready_max_attempts="${JENKINS_READY_MAX_ATTEMPTS:-36}"
  local jenkins_ready_attempt=1
  local jenkins_ready_delay_seconds=5
  while [[ "${jenkins_ready_attempt}" -le "${jenkins_ready_max_attempts}" ]]; do
    if curl --silent --fail --connect-timeout 5 --max-time 10 "http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/login" >/dev/null; then
      echo "]] Jenkins HTTP endpoint is ready."
      return 0
    fi
    echo "waiting for Jenkins HTTP endpoint to become ready (${jenkins_ready_attempt}/${jenkins_ready_max_attempts})..."
    sleep "${jenkins_ready_delay_seconds}"
    jenkins_ready_attempt=$((jenkins_ready_attempt + 1))
  done
  echo "Jenkins did not become ready in time."
  dump_jenkins_logs
  return 1
}

stop_jenkins_binary() {
  if [[ -e "$JENKINS_BINARY_PID_FILE" ]]; then
    local jenkins_binary_pid
    jenkins_binary_pid="$(cat "$JENKINS_BINARY_PID_FILE")"
    if [[ -n "$jenkins_binary_pid" ]] && kill -0 "$jenkins_binary_pid" 2>/dev/null; then
      kill "$jenkins_binary_pid" || true
      local stop_attempt=1
      local max_stop_attempts=20
      while [[ "$stop_attempt" -le "$max_stop_attempts" ]] && kill -0 "$jenkins_binary_pid" 2>/dev/null; do
        sleep 1
        stop_attempt=$((stop_attempt + 1))
      done
      if kill -0 "$jenkins_binary_pid" 2>/dev/null; then
        kill -9 "$jenkins_binary_pid" || true
      fi
    fi
    rm -f "$JENKINS_BINARY_PID_FILE"
  fi
}

start_jenkins_binary() {
  mkdir -p "$JENKINS_BINARY_STATE_DIR" "$JENKINS_DATA_DIR"
  nohup java \
    -Djenkins.install.runSetupWizard=false \
    -Djava.util.logging.config.file="$JENKINS_DATA_DIR/log.properties" \
    -DJENKINS_HOME="$JENKINS_DATA_DIR" \
    -jar "$JENKINS_BINARY_WAR_FILE" \
    --httpPort="$JENKINS_PORT" \
    --httpListenAddress="0.0.0.0" \
    >"$JENKINS_BINARY_LOG_FILE" 2>&1 &
  echo "$!" > "$JENKINS_BINARY_PID_FILE"
}

jenkins_binary_plugin_install() {
  local plugin_name_version="$1"
  local plugin_name="${plugin_name_version%@*}"
  local plugin_version="${plugin_name_version#*@}"

  jenkins_obtain_crumb
  jenkins_curl_or_warn "Requesting Jenkins plugin installation for ${plugin_name}@${plugin_version}" \
    -X POST -H "$CRUMB" --cookie "$COOKIEJAR" \
    -d "<jenkins><install plugin=\"${plugin_name}@${plugin_version}\" /></jenkins>" \
    --header 'Content-Type: text/xml' \
    "http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/pluginManager/installNecessaryPlugins" || return 1

  local plugin_install_attempt=1
  while [[ "$plugin_install_attempt" -le "$JENKINS_BINARY_MAX_PLUGIN_WAIT_ATTEMPTS" ]]; do
    if jenkins_curl --silent "http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/pluginManager/api/json?depth=1" | jq -e ".plugins[] | select(.shortName==\"${plugin_name}\" and .active==true)" >/dev/null; then
      echo "]] Jenkins plugin ${plugin_name} is active."
      return 0
    fi
    echo "Installation of ${plugin_name} plugin still pending... (${plugin_install_attempt}/${JENKINS_BINARY_MAX_PLUGIN_WAIT_ATTEMPTS})"
    sleep 10
    plugin_install_attempt=$((plugin_install_attempt + 1))
  done

  echo "Something is wrong with the Jenkins ${plugin_name} installation..."
  dump_jenkins_logs
  return 1
}

ensure_required_binaries() {
  command -v java >/dev/null || error "java binary not found. Install Java first."
  command -v curl >/dev/null || error "curl binary not found."
  command -v git >/dev/null || error "git binary not found."
  command -v jq >/dev/null || error "jq binary not found."
}

cleanup_jenkins_binary_installation() {
  stop_jenkins_binary
  rm -rf "$JENKINS_DATA_DIR"
  rm -rf "$JENKINS_BINARY_STATE_DIR"
}

run_jenkins_binary_restart() {
  ensure_required_binaries
  if [[ ! -e "$JENKINS_BINARY_WAR_FILE" ]]; then
    error "Jenkins WAR not found at $JENKINS_BINARY_WAR_FILE. Run install first."
  fi
  if [[ ! -e "$JENKINS_DATA_DIR/log.properties" ]]; then
    cp -f .log.properties "$JENKINS_DATA_DIR/log.properties"
  fi
  echo "]] Restarting Jenkins binary process"
  stop_jenkins_binary
  start_jenkins_binary
  wait_for_jenkins_http
  echo "]] Jenkins binary restart complete."
}

if [[ "$JENKINS_BINARY_ACTION" == "--restart" ]]; then
  run_jenkins_binary_restart
  exit 0
fi

if [[ "$JENKINS_BINARY_ACTION" == "--uninstall" ]]; then
  echo "]] Cleaning up the previous Jenkins binary installation"
  cleanup_jenkins_binary_installation
  exit 0
fi

if [[ "$JENKINS_BINARY_ACTION" == "install" ]]; then
  echo "]] Cleaning up the previous Jenkins binary installation"
  cleanup_jenkins_binary_installation
  ensure_required_binaries
  modify_hosts "$JENKINS_DOCKER_CONTAINER_NAME"
  mkdir -p "$JENKINS_DATA_DIR" "$JENKINS_BINARY_STATE_DIR"
  cp -f .log.properties "$JENKINS_DATA_DIR/log.properties" # Enable debug logging
  echo "]] Downloading Jenkins WAR binary"
  curl --fail --show-error --location --output "$JENKINS_BINARY_WAR_FILE" "$JENKINS_BINARY_WAR_DOWNLOAD_URL"
  echo "]] Starting Jenkins binary"
  start_jenkins_binary
  echo "]] Waiting for Jenkins to start properly..."
  wait_for_jenkins_config_file
  wait_for_jenkins_http
  # Credential
  jenkins_obtain_crumb
  # Must do a failing curl to avoid WARNING: No such plugin credentials to install
  jenkins_curl_or_warn "Priming Jenkins credentials plugin installation request" -X POST -H "$CRUMB" --cookie "$COOKIEJAR" -d "<jenkins><install plugin=\"credentials@2.5\" /></jenkins>" --header 'Content-Type: text/xml' "http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/pluginManager/installNecessaryPlugins"
  sleep 30
  jenkins_binary_plugin_install "credentials@$CREDENTIALS_PLUGIN_VERSION"
  echo "]] Adding the needed credentials"
  jenkins_curl_or_warn "Creating Jenkins Anka credentials entry" -X POST -H "$CRUMB" --cookie "$COOKIEJAR" "http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/credentials/store/system/domain/_/createCredentials" \
    --data-urlencode 'json={
    "": "0",
    "credentials": {
      "scope": "GLOBAL",
      "id": "anka",
      "username": "anka",
      "password": "admin",
      "description": "Anka VM User and Password",
      "$class": "com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl"
    }
  }'
  # Clone the jobs examples
  echo "]] Adding example jobs"
  git clone https://github.com/veertuinc/jenkins-job-examples.git "$JENKINS_DATA_DIR/jobs" || true
  # Plugins
  echo "]] Installing Plugins (may take a while)..."
  sleep 80 # Waits for Jenkins initialization and plugin manager to settle
  jenkins_binary_plugin_install "github@$GITHUB_PLUGIN_VERSION"
  jenkins_binary_plugin_install "node-iterator-api@$NODE_ITERATOR_API_PLUGIN_VERSION"
  jenkins_binary_plugin_install "ssh-slaves@$SSH_SLAVES_PLUGIN_VERSION"
  jenkins_binary_plugin_install "workflow-basic-steps@$WORKFLOW_BASIC_STEPS_PLUGIN_VERSION"
  jenkins_binary_plugin_install "workflow-durable-task-step@$WORKFLOW_DURABLE_TASK_STEP_PLUGIN_VERSION"
  jenkins_binary_plugin_install "pipeline-model-definition@$JENKINS_PIPELINE_PLUGIN_VERSION"
  jenkins_binary_plugin_install "anka-build@$JENKINS_PLUGIN_VERSION"
  # Add in the config.xml with the cloud
  echo "]] Adding the configuration you'll need"
  cat > "$JENKINS_DATA_DIR/jenkins.model.JenkinsLocationConfiguration.xml" <<BLOCK
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>address not configured yet &lt;nobody@nowhere&gt;</adminAddress>
  <jenkinsUrl>http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
BLOCK
  sleep 40 # Wait for config.xml to finish bootstrap writes before replacing it
  cp -rf .config.xml "$JENKINS_DATA_DIR/config.xml"
  configure_jenkins_cloud_config "$JENKINS_DATA_DIR/config.xml" "$JENKINS_VM_TEMPLATE_UUID" "$JENKINS_ANKA_MGMT_HOST_FOR_BINARY" "$JENKINS_ANKA_MGMT_PORT_FOR_BINARY"
  stop_jenkins_binary
  start_jenkins_binary
  echo "================================================================================="
  echo "Jenkins UI: http://${JENKINS_DOCKER_CONTAINER_NAME}:${JENKINS_PORT}
Documentation: https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/jenkins"
else
  error "Unsupported action '$JENKINS_BINARY_ACTION'. Use: install (default), --restart, or --uninstall."
fi
