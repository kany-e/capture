#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${RECALL_DERIVED_DATA_PATH:-/tmp/recall-derived-data}"
CONFIGURATION="${RECALL_XCODE_CONFIGURATION:-Debug}"
DESTINATION="${RECALL_XCODE_DESTINATION:-platform=macOS,arch=$(uname -m)}"
PROJECT_PATH="${REPOSITORY_ROOT}/apps/macos/Recall.xcodeproj"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Recall.app"
TEST_BUNDLE="${APP_PATH}/Contents/PlugIns/RecallTests.xctest"
PROFILE_ROOT="${DERIVED_DATA_PATH}/Profiles"

command -v xcodebuild >/dev/null 2>&1 \
  || { printf 'Recall test error: xcodebuild was not found.\n' >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 \
  || { printf 'Recall test error: xcrun was not found.\n' >&2; exit 1; }

printf 'Building Recall tests for %s\n' "${DESTINATION}"
xcodebuild -quiet \
  -project "${PROJECT_PATH}" \
  -scheme Recall \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

[[ -d "${TEST_BUNDLE}" ]] \
  || { printf 'Recall test error: test bundle was not produced at %s\n' "${TEST_BUNDLE}" >&2; exit 1; }

XCTEST="$(xcrun -f xctest)"
mkdir -p "${PROFILE_ROOT}"
export DYLD_LIBRARY_PATH="${APP_PATH}/Contents/MacOS${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
export LLVM_PROFILE_FILE="${PROFILE_ROOT}/Recall-%p.profraw"

printf 'Running Recall unit tests directly with xctest\n'
"${XCTEST}" "${TEST_BUNDLE}"
