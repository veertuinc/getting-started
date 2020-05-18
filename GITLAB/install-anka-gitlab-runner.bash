#!/bin/bash
set -eo pipefail
ANKA_RUNNER_VERSION=${ANKA_RUNNER_VERSION:-"1.0"}
GITLAB_RUNNER_LOCATION="/tmp/anka-gitlab-runner"
GITLAB_RUNNER_DESTINATION="/usr/local/bin/"

cleanup() {
  anka-gitlab-runner stop
  anka-gitlab-runner uninstall || true
  anka-gitlab-runner unregister || true
}

trap cleanup INT

mkdir -p $GITLAB_RUNNER_LOCATION
cd $GITLAB_RUNNER_LOCATION
curl -L -o anka-gitlab-runner.tar.gz https://github.com/veertuinc/gitlab-runner/releases/download/$ANKA_RUNNER_VERSION/gitlab-runner_${ANKA_RUNNER_VERSION}_darwin_amd64.tar.gz
tar -xzvf anka-gitlab-runner.tar.gz
cp -rfp $GITLAB_RUNNER_LOCATION/gitlab-runner-darwin-* $GITLAB_RUNNER_DESTINATION
chmod +x $GITLAB_RUNNER_DESTINATION gitlab-runner-darwin-*
cd ~

# LOCALHOST SHARED RUNNER
anka-gitlab-runner unregister -n localhost-shared
anka-gitlab-runner register --non-interactive \
--url "http://anka-gitlab-ce:8084/" \
--registration-token Egf8JexdqZ9vzrhGgUKU \
--ssh-user anka \
--ssh-password admin \
--name localhost-shared \
--anka-controller-address "https://127.0.0.1:8080/" \
--anka-template-uuid c0847bc9-5d2d-4dbc-ba6a-240f7ff08032 \
--anka-tag base:port-forward-22:brew-git:gitlab \
--executor anka \
--anka-root-ca-path ~/anka-ca-crt.pem \
--anka-cert-path ~/gitlab-crt.pem \
--anka-key-path ~/gitlab-key.pem \
--clone-url "http://anka-gitlab-ce:8084" \
--tag-list localhost-shared

# LOCALHOST SPECIFIC RUNNER
anka-gitlab-runner unregister -n localhost-shared
anka-gitlab-runner register --non-interactive \
--url "http://anka-gitlab-ce:8084/" \
--registration-token zUUFHi6xUmPvELek77o2 \
--ssh-user anka \
--ssh-password admin \
--name localhost-specific \
--anka-controller-address "https://127.0.0.1:8080/" \
--anka-template-uuid c0847bc9-5d2d-4dbc-ba6a-240f7ff08032 \
--anka-tag base:port-forward-22:brew-git:gitlab \
--executor anka \
--anka-root-ca-path ~/anka-ca-crt.pem \
--anka-cert-path ~/gitlab-crt.pem \
--anka-key-path ~/gitlab-key.pem \
--clone-url "http://anka-gitlab-ce:8084" \
--tag-list localhost-specific

anka-gitlab-runner install
anka-gitlab-runner start
