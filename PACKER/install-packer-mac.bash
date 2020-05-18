#!/bin/bash
set -eo pipefail
[[ -z $(which packer) ]] && brew install packer
packer version