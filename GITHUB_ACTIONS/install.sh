#!/usr/bin/env bash
set -exo pipefail
RUNNER_HOME="${RUNNER_HOME:-"$HOME/actions-runner"}"
mkdir -p "${RUNNER_HOME}"
cd "${RUNNER_HOME}"
RUNNER_ARCH=${RUNNER_ARCH:-"$(uname -m)"}
if [ "$RUNNER_ARCH" = "x86_64" ] || [ "$RUNNER_ARCH" = "x64" ]; then
  RUNNER_ARCH="x64"
fi
CURL_CMD="$(curl -s -L https://github.com/actions/runner/releases/latest | grep "curl.*actions-runner-osx-${RUNNER_ARCH}.*.tar.gz" | head -1)"
FULL_FILE_NAME="$(echo "$CURL_CMD" | cut -d/ -f9)"
$CURL_CMD
tar -xzf "$FULL_FILE_NAME" 1>/dev/null
rm -f "$FULL_FILE_NAME"
echo "runner successfully installed"