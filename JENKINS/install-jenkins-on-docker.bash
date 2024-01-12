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
version: '3.9'
services:
  $JENKINS_DOCKER_CONTAINER_NAME:
    container_name: $JENKINS_DOCKER_CONTAINER_NAME
    image: jenkins/jenkins:$JENKINS_TAG_VERSION
    restart: always
    ports:
      - target: $SERVICE_PORT
        published: $JENKINS_PORT
      - target: 50000
        published: 50000
    volumes:
      - type: bind
        source: $JENKINS_DATA_DIR
        target: /var/jenkins_home
    environment:
      JAVA_OPTS: "-Djenkins.install.runSetupWizard=false -Djava.util.logging.config.file=/var/jenkins_home/log.properties"
BLOCK
if [[ "$(uname)" == "Linux" ]]; then
cat >> docker-compose.yml <<BLOCK
    extra_hosts:
      - "host.docker.internal:host-gateway"
BLOCK
fi
  execute-docker-compose pull || true
  execute-docker-compose up -d
  echo "]] Waiting for Jenkins to start properly..."
  while [[ -z "$(ls $JENKINS_DATA_DIR/config.xml 2>/dev/null)" ]]; do
    sleep 10
    echo "waiting for config file to be created..."
  done
  # Credential
  sleep 30
  jenkins_obtain_crumb
  # Must do a failing curl to avoid WARNING: No such plugin credentials to install
  curl -X POST -H "$CRUMB" --cookie "$COOKIEJAR" -d "<jenkins><install plugin=\"credentials@2.5\" /></jenkins>" --header 'Content-Type: text/xml' http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT/pluginManager/installNecessaryPlugins
  sleep 30
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
  # Plugins
  echo "]] Installing Plugins (may take a while)..."
  sleep 80 # Waits for "jenkins.slaves.restarter.JnlpSlaveRestarterInstaller install" to finish
  jenkins_plugin_install "github@$GITHUB_PLUGIN_VERSION"
  jenkins_plugin_install "anka-build@$JENKINS_PLUGIN_VERSION"
  jenkins_plugin_install "pipeline-model-definition@$JENKINS_PIPELINE_PLUGIN_VERSION"
  # Add in the config.xml with the cloud
  echo "]] Adding the configuration you'll need"
  echo "<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>address not configured yet &lt;nobody@nowhere&gt;</adminAddress>
  <jenkinsUrl>http://anka.jenkins:${JENKINS_PORT}/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>" > $JENKINS_DATA_DIR/jenkins.model.JenkinsLocationConfiguration.xml
  sleep 40 # cp: cannot stat ‘.config.xml’: No such file or directory
  cp -rf .config.xml $JENKINS_DATA_DIR/config.xml
  SED_EXTRA="-i"
  [[ $(uname) == "Darwin" ]] && SED_EXTRA="-i \'\'"
  eval sed ${SED_EXTRA} "s/${JENKINS_VM_TEMPLATE_UUID_INTEL}/${JENKINS_VM_TEMPLATE_UUID}/g" $JENKINS_DATA_DIR/config.xml
  execute-docker-compose restart
  docker exec -t anka.jenkins bash -c "mkdir -p ~/.ssh && echo 'Host *' > ~/.ssh/config && echo '    StrictHostKeyChecking no' >> ~/.ssh/config"
  #
  echo "================================================================================="
  echo "Jenkins UI: http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT
Documentation: https://docs.veertu.com/anka/intel/ci-plugins-and-integrations/jenkins"
fi