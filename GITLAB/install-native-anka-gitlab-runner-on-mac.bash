#!/bin/bash
set -eo pipefail
SCRIPT_DIR=$(cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd)
cd $SCRIPT_DIR
. ../shared.bash
# Cleanup
cleanup-runner() {
  anka-gitlab-runner stop || true
  anka-gitlab-runner uninstall || true
  anka-gitlab-runner unregister || true
}
trap cleanup-runner INT
rm -rf $GITLAB_RUNNER_DESTINATION
# Install
if [[ $1 != "--uninstall" ]]; then
  mkdir -p $GITLAB_RUNNER_LOCATION
  cd $GITLAB_RUNNER_LOCATION
  curl -L -o anka-gitlab-runner.tar.gz https://github.com/veertuinc/gitlab-runner/releases/download/$GITLAB_ANKA_RUNNER_VERSION/gitlab-runner_${GITLAB_ANKA_RUNNER_VERSION}_darwin_amd64.tar.gz
  tar -xzvf anka-gitlab-runner.tar.gz
  cp -rfp $GITLAB_RUNNER_LOCATION/gitlab-runner-darwin-* $GITLAB_RUNNER_DESTINATION
  chmod +x $GITLAB_RUNNER_DESTINATION gitlab-runner-darwin-*
  cd ~
fi