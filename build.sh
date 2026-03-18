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
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy the MediaRemoteAdapter dynamic library into the bundle.
# SPM builds it as a .dylib in the release directory.
for dylib in "$SCRIPT_DIR/.build/release/"libMediaRemoteAdapter*.dylib; do
    if [ -f "$dylib" ]; then
        cp "$dylib" "$APP_BUNDLE/Contents/Frameworks/"
    fi
done

# Also copy the Perl script and C helper from the package resources.
ADAPTER_RESOURCES="$SCRIPT_DIR/.build/release/MediaRemoteAdapter_MediaRemoteAdapter.bundle"
if [ -d "$ADAPTER_RESOURCES" ]; then
    cp -R "$ADAPTER_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
fi

# Fix rpath so the binary can find the dylib at runtime.
install_name_tool -add_rpath @executable_path/../Frameworks \
    "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME" 2>/dev/null || true

echo "→ Ad-hoc signing..."
codesign --force --deep --sign - \
    --entitlements "$SCRIPT_DIR/Tabr.entitlements" \
    "$APP_BUNDLE"

echo "→ Launching Tabr.app..."
open "$APP_BUNDLE"
