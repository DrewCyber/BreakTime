#!/bin/bash
# Builds BreakTime and assembles the BreakTime.app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="build/BreakTime.app"

echo "==> swift build (-c $CONFIG)"
swift build -c "$CONFIG"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/BreakTime" "$APP/Contents/MacOS/BreakTime"
cp App/Info.plist "$APP/Contents/Info.plist"

# original app icon, generated programmatically
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
swift Scripts/make_icon.swift "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

echo "==> ad-hoc code sign (stable identifier requirement, so Accessibility survives rebuilds)"
codesign --force --sign - \
  --identifier "com.breaktime.app" \
  --requirements '=designated => identifier "com.breaktime.app"' \
  "$APP"

echo "==> done: $APP"
