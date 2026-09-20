#!/bin/bash
# Dev build that keeps the Accessibility grant: builds the binary, puts it inside build/Flow.app (the bundle
# macOS already trusts), re-signs the bundle, and restarts the LaunchAgent if one is installed.
# The running app's executable cannot be overwritten in place, so a fresh bundle is built beside it and swapped in.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E 'error|Build' || true
[ -d build/Flow.app ] || scripts/make-app.sh
rm -rf build/Flow.app.new
cp -R build/Flow.app build/Flow.app.new
cp .build/release/flow build/Flow.app.new/Contents/MacOS/flow
IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Developer ID Application: [^"]+"' | head -1 | tr -d '"' || true)
[ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --deep --options runtime --sign "$IDENTITY" build/Flow.app.new
rm -rf build/Flow.app.old
mv build/Flow.app build/Flow.app.old
mv build/Flow.app.new build/Flow.app
rm -rf build/Flow.app.old
echo "build/Flow.app updated and signed"
if launchctl print "gui/$(id -u)/dev.flow.agent" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/dev.flow.agent" && echo "agent restarted"
else
  echo "start it with: build/Flow.app/Contents/MacOS/flow login on --agent"
fi
