#!/usr/bin/env bash
# Release build: archive → ad-hoc sign → zip + sha256 in dist/.
# Usage: scripts/build-release.sh [version]   (defaults to MARKETING_VERSION from project.yml)
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
VERSION="${1:-$(grep -E '^\s*MARKETING_VERSION:' project.yml | awk '{print $2}')}"
DIST=dist
APP_NAME=ToReview

rm -rf "$DIST" && mkdir -p "$DIST"
[ -d ToReview.xcodeproj ] || xcodegen generate --quiet

echo "→ Building $APP_NAME $VERSION (Release)"
xcodebuild \
  -project ToReview.xcodeproj \
  -scheme ToReview \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  build | tail -n 5

APP="build/DerivedData/Build/Products/Release/$APP_NAME.app"
cp -R "$APP" "$DIST/"

# Re-sign inside-out so the embedded widget's signature matches the final bundle.
# When a Developer ID certificate becomes available, replace "-" with its name
# and add --options runtime, then notarize (see .notes/roadmap.md).
echo "→ Ad-hoc signing"
codesign --force --sign - --entitlements ToReviewWidget/ToReviewWidget.entitlements \
  "$DIST/$APP_NAME.app/Contents/PlugIns/ToReviewWidget.appex"
codesign --force --sign - -r='designated => identifier "com.ya-makariy.toreview"' --entitlements ToReview/Resources/ToReview.entitlements \
  "$DIST/$APP_NAME.app"
codesign --verify --deep --strict "$DIST/$APP_NAME.app"

ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "→ Zipping $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$DIST/$APP_NAME.app" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"
echo "Done."
