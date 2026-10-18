#!/bin/bash
# Builds build/DoubleTake.app from source.
#   scripts/build-app.sh               native architecture
#   scripts/build-app.sh --universal   Apple silicon + Intel (for releases)
# Set SIGN_IDENTITY to sign with your own certificate; otherwise the app is ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=(--arch "$(uname -m)")
[[ "${1:-}" == "--universal" ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP=build/DoubleTake.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DoubleTake" "$APP/Contents/MacOS/DoubleTake"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
