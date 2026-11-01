#!/usr/bin/env bash
# One-time setup: installs XcodeGen and generates ToReview.xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ Installing XcodeGen via Homebrew"
  brew install xcodegen
fi

echo "→ Generating ToReview.xcodeproj"
xcodegen generate --quiet

echo "Done. Open ToReview.xcodeproj or run scripts/build.sh"
