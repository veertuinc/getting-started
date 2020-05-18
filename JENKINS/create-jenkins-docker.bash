#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
SERVICE_PORT="8080"
docker-compose down &>/dev/null || true
docker stop $JENKINS_DOCKER_CONTAINER_NAME &>/dev/null || true
docker rm $JENKINS_DOCKER_CONTAINER_NAME &>/dev/null || true
rm -rf $JENKINS_DATA_DIR
rm -f docker-compose.yml
if [[ $1 != "--uninstall" ]]; then
  modify_hosts $JENKINS_DOCKER_CONTAINER_NAME
  mkdir -p $JENKINS_DATA_DIR
  cp -f .log.properties $JENKINS_DATA_DIR/log.properties # Enable debug logging
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
      # - JENKINS_OPTS=" --httpPort=-1 --httpsPort=$SERVICE_PORT "
      - JAVA_OPTS="-Djava.util.logging.config.file=/var/jenkins_home/log.properties"
BLOCK
  docker-compose up -d
  echo "Waiting 60 seconds for Jenkins to start properly..."
  sleep 60
  # Disable the "Unlock Jenkins" (initialAdminPassword) 
  sed -i '' 's/NEW/RUNNING/' $JENKINS_DATA_DIR/config.xml
  [[ -z $(grep "<installStateName>RUNNING</installStateName>" $JENKINS_DATA_DIR/config.xml) ]] && echo "sed didn't work" && exit 1
  sed -i '' 's/useSecurity>true/useSecurity>false/' $JENKINS_DATA_DIR/config.xml
  echo 'false' > $JENKINS_DATA_DIR/jenkins.install.runSetupWizard
  cp $JENKINS_DATA_DIR/jenkins.install.UpgradeWizard.state $JENKINS_DATA_DIR/jenkins.install.InstallUtil.lastExecVersion
cat > $JENKINS_DATA_DIR/jenkins.model.JenkinsLocationConfiguration.xml <<BLOCK
<?xml version='1.1' encoding='UTF-8'?>
<jenkins.model.JenkinsLocationConfiguration>
  <adminAddress>address not configured yet &lt;nobody@nowhere&gt;</adminAddress>
  <jenkinsUrl>http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT/</jenkinsUrl>
</jenkins.model.JenkinsLocationConfiguration>
BLOCK
  docker-compose restart
  # Plugins
  echo "Installing Plugins (may take a while)..."
  sleep 80 # Waits for "jenkins.slaves.restarter.JnlpSlaveRestarterInstaller install" to finish
  jenkins_plugin_install "github@$GITHUB_PLUGIN_VERSION"
  jenkins_plugin_install "anka-build@$ANKA_PLUGIN_VERSION"
  jenkins_plugin_install "pipeline-model-definition@$PIPELINE_PLUGIN_VERSION"
  # Credential
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
  git clone https://github.com/veertuinc/jenkins-job-examples.git $JENKINS_DATA_DIR/jobs
  docker-compose stop
  # Add in the config.xml with the cloud 
  cp -rf .config.xml $JENKINS_DATA_DIR/config.xml
  docker-compose start
  #
  echo "================================================================================="
  echo "Jenkins is now accessible at: http://$JENKINS_DOCKER_CONTAINER_NAME:$JENKINS_PORT
Documentation: https://ankadocs.veertu.com/docs/anka-build-cloud/ci-plugins/jenkins"
fi