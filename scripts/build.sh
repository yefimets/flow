#!/bin/bash
# Builds the terminal binary and signs it with a stable identity (Developer ID if present, else Apple
# Development), so macOS keeps the Accessibility grant across rebuilds instead of asking every time.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release 2>&1 | grep -E 'error|Build' || true
IDENTITY=$(security find-identity -v -p codesigning | grep -oE '"(Developer ID Application|Apple Development): [^"]+"' | head -1 | tr -d '"' || true)
if [ -n "$IDENTITY" ]; then
  codesign --force --options runtime --sign "$IDENTITY" .build/release/flow
  echo "signed .build/release/flow with: $IDENTITY"
else
  echo "no certificate found; binary is ad-hoc signed and may need the Accessibility toggle after rebuilds"
fi
