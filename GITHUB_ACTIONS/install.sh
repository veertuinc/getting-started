#!/usr/bin/env sh
set -x

failed() {
  error=${1:-Undefined error}
  echo "Failed: $error" >&2
  exit 1
}

RUNNER_HOME=${RUNNER_HOME:-"$HOME/actions-runner"}
mkdir -p "$RUNNER_HOME"
cd "$RUNNER_HOME" || failed "enter $RUNNER_HOME directory"

RUNNER_ARCH=${RUNNER_ARCH:-"$(uname -m)"}
if [ "$RUNNER_ARCH" = "arm64" ]; then
  RUNNER_SHASUM="4e4a5e7de762c800c4d41196bf6ed070581a1e3c4a2169178d3dbc27509a55a8"

elif [ "$RUNNER_ARCH" = "x86_64" ] || [ "$RUNNER_ARCH" = "x64" ]; then
  RUNNER_ARCH="x64"
  RUNNER_SHASUM="842bfb1d707fd7af153bb819cdc3e652bc451b9110b76fcb4b4a4ba0c4da553a"

else
  failed "unsupported arch: $RUNNER_ARCH"
fi

curl -o actions-runner-osx-"$RUNNER_ARCH"-2.306.0.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.306.0/actions-runner-osx-"$RUNNER_ARCH"-2.306.0.tar.gz

echo "$RUNNER_SHASUM  actions-runner-osx-$RUNNER_ARCH-2.306.0.tar.gz" |
  shasum -a 256 -c || failed "validate checksum"

tar xzf ./actions-runner-osx-"$RUNNER_ARCH"-2.306.0.tar.gz || failed "extract archive"
echo "runner successfully installed"
