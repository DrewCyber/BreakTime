#!/bin/bash
# Builds BreakTime and assembles the BreakTime.app bundle.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
ARCHS="${2:-native}"          # native | universal (arm64 + x86_64)
APP_VERSION="${APP_VERSION:-}"  # optional, e.g. 0.0.1 (stamped into Info.plist)
APP="build/BreakTime.app"

echo "==> swift build (-c $CONFIG, $ARCHS)"
if [[ "$ARCHS" == "universal" ]]; then
  swift build -c "$CONFIG" --arch arm64 --arch x86_64
else
  swift build -c "$CONFIG"
fi

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp ".build/$CONFIG/BreakTime" "$APP/Contents/MacOS/BreakTime"
cp App/Info.plist "$APP/Contents/Info.plist"

if [[ -n "$APP_VERSION" ]]; then
  plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP/Contents/Info.plist"
  echo "==> version: $APP_VERSION"
fi

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
