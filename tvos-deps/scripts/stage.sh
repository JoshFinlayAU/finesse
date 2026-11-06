#!/bin/bash
# Runs steps in order and writes STAGE-OK or STAGE-FAILED at the end of its output.
# Usage: stage.sh "<script> <slice>" ... Started under nohup on the Mac, so it outlives the session that started it.
cd "$(dirname "$0")" || exit 1
for step in "$@"; do
  echo "=== $step $(date +%H:%M:%S)"
  # shellcheck disable=SC2086
  if ! bash ./$step; then
    echo "STAGE-FAILED $step"
    exit 1
  fi
done
echo "STAGE-OK $(date +%H:%M:%S)"
