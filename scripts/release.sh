#!/bin/bash
# Cuts a release: bumps the version, builds and notarizes Flow.app, tags, and publishes to GitHub Releases.
#   scripts/release.sh 0.2.0
# Needs: a Developer ID certificate, the flow-notary keychain profile, and `gh auth login` on the right account.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh X.Y.Z}"
sed -i '' "s/static let version = \"[^\"]*\"/static let version = \"$VERSION\"/" Sources/flow/Version.swift
grep -q "## $VERSION" CHANGELOG.md || { echo "add a '## $VERSION' section to CHANGELOG.md first"; exit 1; }
# Keep the README's download button and release line current.
sed -i '' -E "s#releases/download/v[0-9.]+/Flow-[0-9.]+\\.zip#releases/download/v$VERSION/Flow-$VERSION.zip#; s#Download_Flow-[0-9.]+-7AA2F7#Download_Flow-$VERSION-7AA2F7#; s#alt=\"Download Flow [0-9.]+\"#alt=\"Download Flow $VERSION\"#" README.md
sed -i '' -E "s#\*\*Latest release: \[[0-9.]+\]\(https://github.com/yefimets/flow/releases/tag/v[0-9.]+\)\*\*#**Latest release: [$VERSION](https://github.com/yefimets/flow/releases/tag/v$VERSION)**#; s#Flow-[0-9.]+\.zip\)#Flow-$VERSION.zip)#" README.md
scripts/make-app.sh
scripts/notarize.sh
cp build/Flow.zip "build/Flow-$VERSION.zip"
git add -A
git commit -q -m "Release $VERSION" || true
git tag -a "v$VERSION" -m "Flow $VERSION"
git push origin main --tags
# Release notes: the changelog section for this version.
awk "/^## $VERSION/{flag=1; next} /^## /{flag=0} flag" CHANGELOG.md > build/notes.md
gh release create "v$VERSION" "build/Flow-$VERSION.zip" --title "Flow $VERSION" --notes-file build/notes.md
echo "published https://github.com/yefimets/flow/releases/tag/v$VERSION"
