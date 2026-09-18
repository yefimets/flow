#!/bin/bash
# Builds Flow.app into build/, signs it with the best identity in the keychain, and verifies the signature.
#   scripts/make-app.sh                 # auto-picks Developer ID, else Apple Development, else ad-hoc
#   scripts/make-app.sh "Developer ID Application: Name (TEAMID)"
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E 'error|Compiling|Build' || true
APP=build/Flow.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/flow "$APP/Contents/MacOS/flow"
VERSION=$(grep -oE 'version = "[^"]+"' Sources/flow/Version.swift | cut -d'"' -f2)
sed "s#<string>0.1.0</string>#<string>$VERSION</string>#" Resources/Info.plist > "$APP/Contents/Info.plist"
if [ ! -f Resources/AppIcon.icns ]; then
  swiftc -O scripts/make-icon.swift -o build/make-icon 2>/dev/null && build/make-icon build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
IDENTITY="${1:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Developer ID Application: [^"]+"' | head -1 | tr -d '"' || true)
fi
if [ -z "$IDENTITY" ]; then
  IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
fi
if [ -z "$IDENTITY" ]; then IDENTITY="-"; echo "no certificate found, signing ad-hoc"; else echo "signing with: $IDENTITY"; fi
if [ "$IDENTITY" = "-" ]; then codesign --force --deep --options runtime --sign - "$APP"; else codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"; fi
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
echo "built $APP"
