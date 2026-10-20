#!/bin/bash
# Wraps build/DoubleTake.app in dist/DoubleTake.dmg: open it, drag the app onto the Applications
# shortcut next to it, done. Run scripts/build-app.sh first (package-release.sh does both).
# Finder lays out the window, so this needs a logged-in session (it can't run headless).
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/DoubleTake.app
VOLUME=DoubleTake
OUT=dist/DoubleTake.dmg
[[ -d "$APP" ]] || { echo "error: $APP is missing; run scripts/build-app.sh first" >&2; exit 1; }
[[ -e "/Volumes/$VOLUME" ]] && hdiutil detach "/Volumes/$VOLUME" -quiet

# Finder records the image's path in the window layout, so build somewhere that doesn't name this Mac's user folders.
WORK="$(mktemp -d /tmp/doubletake-dmg.XXXXXX)"
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

mkdir -p "$WORK/stage/.background"
ditto "$APP" "$WORK/stage/DoubleTake.app"
ln -s /Applications "$WORK/stage/Applications"
cp Resources/dmg-background.tiff "$WORK/stage/.background/background.tiff"

hdiutil create -quiet -volname "$VOLUME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -noautoopen "$WORK/rw.dmg"
# Finder can take a moment to notice a newly mounted disk.
for _ in {1..20}; do
    osascript -e "tell application \"Finder\" to get disk \"$VOLUME\"" >/dev/null 2>&1 && break
    sleep 0.5
done

# Icon positions match the arrow in Resources/dmg-background.tiff (scripts/make-dmg-background.swift).
osascript <<OSA
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 840, 568}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "DoubleTake.app" of container window to {170, 185}
        set position of item "Applications" of container window to {470, 185}
        update without registering applications
        delay 1
        close
    end tell
end tell
OSA

# Finder removes a volume icon that's already there while it lays out the window, so add it afterwards.
cp Resources/AppIcon.icns "/Volumes/$VOLUME/.VolumeIcon.icns"
SetFile -a C "/Volumes/$VOLUME"
# Finder saves the layout in .DS_Store a moment after the window closes; detaching sooner loses it.
for _ in {1..20}; do [[ -f "/Volumes/$VOLUME/.DS_Store" ]] && break; sleep 0.5; done
sleep 2
sync
hdiutil detach -quiet "/Volumes/$VOLUME"
mkdir -p dist
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT"
echo "Wrote $OUT"
