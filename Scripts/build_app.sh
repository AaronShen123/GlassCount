#!/bin/bash
# Builds a release GlassCount.app next to this repo (./build/GlassCount.app) from the Swift package.
# No Xcode needed — only the Command Line Tools. The app is ad-hoc signed (fine for local use).
set -euo pipefail
cd "$(dirname "$0")/.."
# Universal binary (Apple silicon + Intel)
ARCHS="--arch arm64 --arch x86_64"
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/GlassCount"
APP="build/GlassCount.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/GlassCount"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/GlassCount"))"
ditto -c -k --keepParent "$APP" build/GlassCount.zip
echo "Zipped build/GlassCount.zip"
