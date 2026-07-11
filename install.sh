#!/bin/bash
# BrightnessBar installer — builds from source and installs to /Applications.
#
# Run from a clone:        ./install.sh
# Or without cloning:      curl -fsSL https://raw.githubusercontent.com/hiteshsuthar1410/MacOS-External-Display-Brightness-Controller/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/hiteshsuthar1410/MacOS-External-Display-Brightness-Controller.git"
APP_NAME="BrightnessBar"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "This installer is for macOS."
[[ "$(uname -m)" == "arm64" ]] || fail "BrightnessBar requires an Apple Silicon Mac (DDC/CI is driven through the Apple Silicon display coprocessor)."

# Swift toolchain (Xcode command-line tools) is required to build.
if ! command -v swift >/dev/null 2>&1; then
    fail "The Swift toolchain was not found. Install the Xcode command-line tools first:  xcode-select --install"
fi

# If this script isn't running inside a checkout, clone one to a temp dir.
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -z "$SRC_DIR" || ! -f "$SRC_DIR/Package.swift" ]]; then
    command -v git >/dev/null 2>&1 || fail "git is required."
    TMP_DIR="$(mktemp -d)"
    trap 'rm -rf "$TMP_DIR"' EXIT
    say "Cloning $REPO_URL"
    git clone --quiet --depth 1 "$REPO_URL" "$TMP_DIR/src"
    SRC_DIR="$TMP_DIR/src"
fi
cd "$SRC_DIR"

say "Building $APP_NAME (release)"
./Scripts/make-app.sh

# Prefer /Applications; fall back to ~/Applications if not writable.
DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

# Replace any running/previous copy.
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    say "Stopping the running $APP_NAME"
    pkill -x "$APP_NAME" || true
    sleep 1
fi
rm -rf "$DEST/$APP_NAME.app"
cp -R "dist/$APP_NAME.app" "$DEST/"

say "Installed $DEST/$APP_NAME.app"
open "$DEST/$APP_NAME.app"
say "Done — look for the ☀️ icon in the menu bar."
say "Tip: enable “Launch at login” from the app's menu."
