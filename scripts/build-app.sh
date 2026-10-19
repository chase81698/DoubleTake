#!/bin/bash
# Builds build/DoubleTake.app from source.
#   scripts/build-app.sh               native architecture
#   scripts/build-app.sh --universal   Apple silicon + Intel (for releases)
# Set SIGN_IDENTITY to sign with your own certificate; otherwise the app is ad-hoc signed.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCHS=("$(uname -m)")
[[ "${1:-}" == "--universal" ]] && ARCHS=(arm64 x86_64)

# One architecture per build, then lipo them together: some SwiftPM versions reject
# multi-architecture builds of targets that set a Swift language mode.
# Each binary is copied aside right away, since some versions build every architecture into the same folder.
SLICES="$(mktemp -d)"
trap 'rm -rf "$SLICES"' EXIT
BINARIES=()
for arch in "${ARCHS[@]}"; do
    swift build -c release --arch "$arch"
    cp "$(swift build -c release --arch "$arch" --show-bin-path)/DoubleTake" "$SLICES/DoubleTake-$arch"
    BINARIES+=("$SLICES/DoubleTake-$arch")
done

APP=build/DoubleTake.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
lipo -create -output "$APP/Contents/MacOS/DoubleTake" "${BINARIES[@]}"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/io.github.chase81698.DoubleTake.agent.plist "$APP/Contents/Library/LaunchAgents/"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"

echo "Built $APP"
