#!/bin/bash
# Builds a universal app and packages it for a GitHub release:
#   dist/DoubleTake.dmg  the download for people: open it and drag the app into Applications
#   dist/DoubleTake.zip  what install.sh fetches from https://github.com/<repo>/releases/latest/download/DoubleTake.zip
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh --universal
mkdir -p dist
rm -f dist/DoubleTake.zip
ditto -c -k --keepParent build/DoubleTake.app dist/DoubleTake.zip
echo "Wrote dist/DoubleTake.zip"
scripts/make-dmg.sh
VERSION="$(defaults read "$PWD/build/DoubleTake.app/Contents/Info" CFBundleShortVersionString)"
echo "Publish with: gh release create v$VERSION dist/DoubleTake.dmg dist/DoubleTake.zip"
