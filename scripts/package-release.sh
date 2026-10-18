#!/bin/bash
# Builds a universal app and zips it as dist/DoubleTake.zip, ready to attach to a GitHub release.
# install.sh downloads it from https://github.com/<repo>/releases/latest/download/DoubleTake.zip
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh --universal
mkdir -p dist
rm -f dist/DoubleTake.zip
ditto -c -k --keepParent build/DoubleTake.app dist/DoubleTake.zip
echo "Wrote dist/DoubleTake.zip"
echo "Publish with: gh release create v\$(defaults read \"\$PWD/build/DoubleTake.app/Contents/Info\" CFBundleShortVersionString) dist/DoubleTake.zip"
