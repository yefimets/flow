#!/bin/bash
# Notarizes build/Flow.app with Apple, staples the ticket, and produces build/Flow.zip for distribution.
# One-time setup (prompts for an app-specific password from appleid.apple.com, stored in your keychain):
#   xcrun notarytool store-credentials flow-notary --apple-id YOUR@APPLE.ID --team-id 3MJC29B2BT
# Then:
#   scripts/make-app.sh && scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Flow.app
PROFILE="${1:-flow-notary}"
SIG=$(codesign -dvv "$APP" 2>&1 || true)
case "$SIG" in *"Developer ID Application"*) ;; *) echo "Flow.app is not signed with a Developer ID certificate; run scripts/make-app.sh after creating one"; exit 1;; esac
rm -f build/Flow.zip
ditto -c -k --keepParent "$APP" build/Flow.zip
echo "submitting to Apple notary service (usually 1-5 minutes)…"
xcrun notarytool submit build/Flow.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f build/Flow.zip
ditto -c -k --keepParent "$APP" build/Flow.zip
spctl --assess --type execute --verbose=2 "$APP"
echo "ready to share: build/Flow.zip"
