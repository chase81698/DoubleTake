#!/bin/bash
# Installs DoubleTake: the app goes in /Applications, the `doubletake` command in /usr/local/bin.
#
#   One line, no Xcode needed:
#     curl -fsSL https://raw.githubusercontent.com/chase81698/DoubleTake/main/install.sh | bash
#   From a clone (builds from source):
#     ./install.sh
#   Remove it again:
#     ./install.sh --uninstall
set -euo pipefail

REPO="chase81698/DoubleTake"
BUNDLE_ID="io.github.chase81698.DoubleTake"
APP_DEST="/Applications/DoubleTake.app"
CLI_DEST="/usr/local/bin/doubletake"

say() { printf '\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
# Runs a command, retrying as administrator if the user can't write there: sudo in a terminal,
# the standard macOS password dialog when there is no terminal to type into.
as_admin() {
    "$@" 2>/dev/null && return 0
    if sudo -n true 2>/dev/null || (: </dev/tty) 2>/dev/null; then
        sudo "$@"
    else
        local cmd
        cmd="$(printf '%q ' "$@" | sed 's/\\/\\\\/g; s/"/\\"/g')"
        osascript -e "do shell script \"$cmd\" with administrator privileges" >/dev/null
    fi
}

quit_app() {
    pgrep -xq DoubleTake || return 0
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq DoubleTake || return 0; sleep 0.5; done
    pkill -x DoubleTake || true
}

cdhash() { codesign -dvvv "$1" 2>&1 | sed -n 's/^CDHash=//p'; }

if [[ "${1:-}" == "--uninstall" ]]; then
    say "Removing DoubleTake"
    quit_app
    launchctl bootout "gui/$(id -u)/$BUNDLE_ID.agent" >/dev/null 2>&1 || true
    [[ -e "$APP_DEST" ]] && as_admin rm -rf "$APP_DEST"
    [[ -L "$CLI_DEST" || -e "$CLI_DEST" ]] && as_admin rm -f "$CLI_DEST"
    # Administrator approvals: root-owned scripts and their sudoers rule.
    if [[ -e "/Library/Application Support/DoubleTake" ]] || ls /private/etc/sudoers.d/doubletake-* >/dev/null 2>&1; then
        as_admin sh -c 'rm -f /private/etc/sudoers.d/doubletake-*; rm -rf "/Library/Application Support/DoubleTake"'
    fi
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    say "Done. Your shortcuts are kept in ~/Library/Application Support/DoubleTake (delete it to start fresh)."
    exit 0
fi

[[ "$(uname)" == "Darwin" ]] || die "DoubleTake is a macOS app."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

SOURCE_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "$(dirname "${BASH_SOURCE[0]}")/Package.swift" ]]; then
    SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

build_from() {
    command -v swift >/dev/null 2>&1 || die "Building needs Swift. Install it with: xcode-select --install"
    say "Building from source (this takes a minute the first time)"
    "$1/scripts/build-app.sh"
    NEW_APP="$1/build/DoubleTake.app"
}

if [[ -n "$SOURCE_DIR" ]]; then
    build_from "$SOURCE_DIR"
elif curl -fsSL -o "$WORK/DoubleTake.zip" "https://github.com/$REPO/releases/latest/download/DoubleTake.zip"; then
    say "Downloaded the latest release"
    ditto -x -k "$WORK/DoubleTake.zip" "$WORK"
    NEW_APP="$WORK/DoubleTake.app"
else
    say "No release found, fetching the source instead"
    git clone --depth 1 "https://github.com/$REPO.git" "$WORK/src" >/dev/null 2>&1 || die "Couldn't download $REPO."
    build_from "$WORK/src"
fi
[[ -d "$NEW_APP" ]] || die "Build failed."

# A new ad-hoc signature invalidates the old Accessibility grant; clear it so macOS asks again cleanly.
if [[ -d "$APP_DEST" && "$(cdhash "$APP_DEST")" != "$(cdhash "$NEW_APP")" ]] \
    && codesign -dvvv "$NEW_APP" 2>&1 | grep -q "Signature=adhoc"; then
    RESET_PERMISSION=1
fi

say "Installing to $APP_DEST"
quit_app
[[ -e "$APP_DEST" ]] && as_admin rm -rf "$APP_DEST"
as_admin ditto "$NEW_APP" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
[[ -n "${RESET_PERMISSION:-}" ]] && tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

CLI_TARGET="$APP_DEST/Contents/MacOS/DoubleTake"
if [[ "$(readlink "$CLI_DEST" 2>/dev/null)" != "$CLI_TARGET" ]]; then
    say "Linking the command line tool to $CLI_DEST"
    as_admin mkdir -p "$(dirname "$CLI_DEST")"
    as_admin ln -sf "$CLI_TARGET" "$CLI_DEST"
fi
case ":$PATH:" in
    *":$(dirname "$CLI_DEST"):"*) ;;
    *) echo "   Add /usr/local/bin to your PATH to use \`doubletake\` from any shell." ;;
esac

say "Starting DoubleTake"
open "$APP_DEST"
cat <<MSG

  DoubleTake runs quietly in the background (no menu bar or Dock icon) and starts at login.
  Open it from Applications or with \`doubletake open\` to edit shortcuts.
  The first time, macOS asks you to allow it under
  System Settings › Privacy & Security › Accessibility. Switch it on and you're done.

  Try:  doubletake list      doubletake help      doubletake help --llm

MSG
