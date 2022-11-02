#!/usr/bin/env sh

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
  RUNNER_SHASUM="e124418a44139b4b80a7b732cfbaee7ef5d2f10eab6bcb3fd67d5541493aa971"

elif [ "$RUNNER_ARCH" = "x86_64" ] || [ "$RUNNER_ARCH" = "x64" ]; then
  RUNNER_ARCH="x64"
  RUNNER_SHASUM="0fb116f0d16ac75bcafa68c8db7c816f36688d3674266fe65139eefec3a9eb04"

else
  failed "unsupported arch: $RUNNER_ARCH"
fi

curl -o actions-runner-osx-"$RUNNER_ARCH"-2.298.2.tar.gz \
  -L https://github.com/actions/runner/releases/download/v2.298.2/actions-runner-osx-"$RUNNER_ARCH"-2.298.2.tar.gz

echo "$RUNNER_SHASUM  actions-runner-osx-$RUNNER_ARCH-2.298.2.tar.gz" |
  shasum -a 256 -c || failed "validate checksum"

tar xzf ./actions-runner-osx-"$RUNNER_ARCH"-2.298.2.tar.gz || failed "extract archive"
