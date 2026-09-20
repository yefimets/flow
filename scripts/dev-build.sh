#!/bin/bash
# Dev build that keeps the Accessibility grant: builds the binary, puts it inside build/Flow.app (the bundle
# macOS already trusts), re-signs the bundle, and restarts the LaunchAgent if one is installed.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E 'error|Build' || true
[ -d build/Flow.app ] || scripts/make-app.sh
cp .build/release/flow build/Flow.app/Contents/MacOS/flow
IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Developer ID Application: [^"]+"' | head -1 | tr -d '"' || true)
[ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
[ -z "$IDENTITY" ] && IDENTITY="-"
codesign --force --deep --options runtime --sign "$IDENTITY" build/Flow.app
echo "build/Flow.app updated and signed"
if launchctl print "gui/$(id -u)/dev.flow.agent" >/dev/null 2>&1; then
  launchctl kickstart -k "gui/$(id -u)/dev.flow.agent" && echo "agent restarted"
else
  echo "start it with: build/Flow.app/Contents/MacOS/flow login on --agent"
fi
