#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DERIVED_DATA_PATH="${MEMA_DERIVED_DATA_PATH:-/tmp/mema-derived-data}"
CONFIGURATION="${MEMA_XCODE_CONFIGURATION:-Debug}"
DESTINATION="${MEMA_XCODE_DESTINATION:-platform=macOS,arch=$(uname -m)}"
PROJECT_PATH="${REPOSITORY_ROOT}/apps/macos/Mema.xcodeproj"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Mema.app"
TEST_BUNDLE="${APP_PATH}/Contents/PlugIns/MemaTests.xctest"
PROFILE_ROOT="${DERIVED_DATA_PATH}/Profiles"

command -v xcodebuild >/dev/null 2>&1 \
  || { printf 'Mema test error: xcodebuild was not found.\n' >&2; exit 1; }
command -v xcrun >/dev/null 2>&1 \
  || { printf 'Mema test error: xcrun was not found.\n' >&2; exit 1; }

printf 'Building Mema tests for %s\n' "${DESTINATION}"
xcodebuild -quiet \
  -project "${PROJECT_PATH}" \
  -scheme Mema \
  -configuration "${CONFIGURATION}" \
  -destination "${DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing

[[ -d "${TEST_BUNDLE}" ]] \
  || { printf 'Mema test error: test bundle was not produced at %s\n' "${TEST_BUNDLE}" >&2; exit 1; }

XCTEST="$(xcrun -f xctest)"
mkdir -p "${PROFILE_ROOT}"
export DYLD_LIBRARY_PATH="${APP_PATH}/Contents/MacOS${DYLD_LIBRARY_PATH:+:${DYLD_LIBRARY_PATH}}"
export LLVM_PROFILE_FILE="${PROFILE_ROOT}/Mema-%p.profraw"

printf 'Running Mema unit tests directly with xctest\n'
"${XCTEST}" "${TEST_BUNDLE}"
