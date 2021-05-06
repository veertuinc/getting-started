#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd "$SCRIPT_DIR"
. ../shared.bash
SERVICE_PORT="8080"
echo "]] Cleaning up the previous Jenkins installation"
execute-docker-compose down &>/dev/null || true
docker stop $JENKINS_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $JENKINS_DOCKER_CONTAINER_NAME &>/dev/null || true
rm -rf $JENKINS_DATA_DIR
rm -f docker-compose.yml
if [[ $1 != "--uninstall" ]]; then
  modify_hosts $JENKINS_DOCKER_CONTAINER_NAME
  mkdir -p $JENKINS_DATA_DIR
  cp -f .log.properties $JENKINS_DATA_DIR/log.properties # Enable debug logging
  echo "]] Starting the Jenkins Docker container"
cat > docker-compose.yml <<BLOCK
version: '3.7'
services:
  $JENKINS_DOCKER_CONTAINER_NAME:
    container_name: $JENKINS_DOCKER_CONTAINER_NAME
    image: jenkins/jenkins:$JENKINS_TAG_VERSION
    restart: always
    ports:
      - "$JENKINS_PORT:$SERVICE_PORT"
      - "50000:50000"
    volumes:
      - $JENKINS_DATA_DIR:/var/jenkins_home
    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false -Djava.util.logging.config.file=/var/jenkins_home/log.properties"
BLOCK
  execute-docker-compose pull || true
  execute-docker-compose up -d
  echo "]] Waiting for Jenkins to start properly..."
  while [[ -z "$(ls $JENKINS_DATA_DIR/config.xml 2>/dev/null)" ]]; do
    sleep 10
    echo "waiting for config file to be created..."
  done
  # Credential
  jenkins_plugin_install "credentials@$CREDENTIALS_PLUGIN_VERSION"
  echo "]] Adding the needed credentials"
  curl -X POST -H "$CRUMB" --cookie "$COOKIEJAR" http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT/credentials/store/system/domain/_/createCredentials \
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
  git clone https://github.com/veertuinc/jenkins-job-examples.git $JENKINS_DATA_DIR/jobs
  execute-docker-compose stop
  # Add in the config.xml with the cloud
  echo "]] Adding the configuration you'll need"
  cp -rf .config.xml $JENKINS_DATA_DIR/config.xml
  execute-docker-compose start
  # Plugins
  echo "]] Installing Plugins (may take a while)..."
  sleep 80 # Waits for "jenkins.slaves.restarter.JnlpSlaveRestarterInstaller install" to finish
  jenkins_plugin_install "github@$GITHUB_PLUGIN_VERSION"
  jenkins_plugin_install "anka-build@$JENKINS_PLUGIN_VERSION"
  jenkins_plugin_install "pipeline-model-definition@$JENKINS_PIPELINE_PLUGIN_VERSION"
  execute-docker-compose restart
  #
  echo "================================================================================="
  echo "Jenkins UI: http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT
Documentation: https://ankadocs.veertu.com/docs/ci-plugins-and-integrations/jenkins"
fi