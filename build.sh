#!/bin/bash
# Builds Tabr as a proper .app bundle and ad-hoc signs it.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/Tabr.app"
BINARY_NAME="Tabr"

echo "→ Building..."
swift build -c release --package-path "$SCRIPT_DIR" 2>&1

BINARY="$SCRIPT_DIR/.build/release/$BINARY_NAME"

echo "→ Creating app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - \
    --entitlements "$SCRIPT_DIR/Tabr.entitlements" \
    "$APP_BUNDLE"

echo "→ Launching Tabr.app..."
open "$APP_BUNDLE"
