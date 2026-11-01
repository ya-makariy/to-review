#!/usr/bin/env bash
# Debug build, then restart the app AND the widget extension process.
# macOS keeps the widget extension running after a rebuild, so without the kill
# widgets keep executing the previous binary.
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build.sh "$@"
pkill -x ToReviewWidget || true
pkill -x ToReview || true
sleep 1
open build/DerivedData/Build/Products/Debug/ToReview.app
echo "Launched build/DerivedData/Build/Products/Debug/ToReview.app"
