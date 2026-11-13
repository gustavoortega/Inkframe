#!/bin/bash
# Builds Inkframe.app from source and signs it with a stable identity.
# A stable signature keeps the Screen Recording grant across rebuilds; ad-hoc signing would reset it every build.
set -euo pipefail

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to a code-signing identity (security find-identity -v -p codesigning)}"

cd "$(dirname "$0")/.."
swift build -c release

APP="build/Inkframe.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Inkframe "$APP/Contents/MacOS/Inkframe"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --options runtime --timestamp=none \
  --entitlements Resources/Inkframe.entitlements \
  --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
echo "Built $APP"
