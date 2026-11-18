#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
scratch="/Users/tinyserve/.hermes/cache/scratch/dictation-camera"
mkdir -p "$scratch"
swiftc -swift-version 6 -parse-as-library \
  "$repo_root/native/App/DictationCameraOCR.swift" \
  "$repo_root/native/ci/dictation_camera_harness.swift" \
  -o "$scratch/dictation-camera-tests"
if [[ $# -eq 0 ]]; then
  "$scratch/dictation-camera-tests" --fixture "$repo_root/native/App/DictationCameraFixture.png"
else
  "$scratch/dictation-camera-tests" "$@"
fi
