#!/bin/bash
# Builds the terminal binary and signs it with a stable identity (Developer ID if present, else Apple
# Development), so macOS keeps the Accessibility grant across rebuilds instead of asking every time.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f Vendor/whisper/lib/libwhisper.a ] || scripts/build-whisper.sh
swift build -c release 2>&1 | grep -E 'error|Build'
[ "${PIPESTATUS[0]}" -eq 0 ] || { echo 'build failed'; exit 1; }
# Apple Development first: every Xcode user has one, and switching identities would re-trigger the grant.
IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Apple Development: [^"]+"' | head -1 | tr -d '"' || true)
[ -z "$IDENTITY" ] && IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"Developer ID Application: [^"]+"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" .build/release/flow
  echo "signed .build/release/flow with: $IDENTITY"
else
  echo "no certificate found; binary is ad-hoc signed and may need the Accessibility toggle after rebuilds"
fi
