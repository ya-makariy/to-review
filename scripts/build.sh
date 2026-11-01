#!/usr/bin/env bash
# Debug build from the command line. Uses the full Xcode toolchain even when
# xcode-select points at the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
[ -d ToReview.xcodeproj ] || xcodegen generate --quiet

xcodebuild \
  -project ToReview.xcodeproj \
  -scheme ToReview \
  -configuration "${CONFIGURATION:-Debug}" \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_IDENTITY="-" \
  "$@" build | tail -n 40
