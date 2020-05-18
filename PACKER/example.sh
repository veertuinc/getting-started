#!/bin/bash
set -eo pipefail
echo "RUNNING SCRIPT INSIDE OF $(hostname)"
echo "TEST_VAR: $TEST_VAR"
ls -laht .
sleep 5
echo "RAN!"