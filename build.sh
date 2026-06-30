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
# Start from a clean bundle. cp -R can't overwrite the read-only resources copied
# by a previous build (e.g. run.pl), so a stale bundle would break re-runs.
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# --- Package MediaRemoteAdapter as a proper .framework (macOS 26 fix) ---
# SPM builds the adapter as a loose .dylib. If we copy it loose into Frameworks,
# Bundle(for: MediaController.self) can't find a bundle for it and falls back to the
# main app bundle, so the adapter hands its perl helper the path to the MAIN
# EXECUTABLE. That binary depends on @rpath/libMediaRemoteAdapter.dylib, and macOS 26
# refuses to expand @rpath when a foreign process (perl) dlopen()s it ("security
# policy does not allow @ path expansion") — Now Playing then silently dies.
#
# Wrapping the dylib in a real (versioned) .framework makes Bundle(for:) resolve to
# the framework, so the adapter hands perl the framework binary's absolute path, which
# loads without any @rpath expansion. This matches the adapter's documented "Embed &
# Sign" integration and needs no run.pl patch.
FW_NAME="MediaRemoteAdapter"
FW="$APP_BUNDLE/Contents/Frameworks/$FW_NAME.framework"
FW_REF="@rpath/$FW_NAME.framework/Versions/A/$FW_NAME"
for dylib in "$SCRIPT_DIR/.build/release/"libMediaRemoteAdapter*.dylib; do
    [ -f "$dylib" ] || continue
    mkdir -p "$FW/Versions/A/Resources"
    cp "$dylib" "$FW/Versions/A/$FW_NAME"
    ln -sf A "$FW/Versions/Current"
    ln -sf "Versions/Current/$FW_NAME" "$FW/$FW_NAME"
    ln -sf Versions/Current/Resources "$FW/Resources"
    cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.tabr.$FW_NAME</string>
    <key>CFBundleName</key><string>$FW_NAME</string>
    <key>CFBundleExecutable</key><string>$FW_NAME</string>
    <key>CFBundlePackageType</key><string>FMWK</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
</dict>
</plist>
PLIST
    # Point the framework's id and the app's dependency at the framework path.
    install_name_tool -id "$FW_REF" "$FW/Versions/A/$FW_NAME"
    install_name_tool -change @rpath/"$(basename "$dylib")" "$FW_REF" \
        "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
    break
done

# Copy the Perl helper resource bundle. The adapter's generated Bundle.module locates
# run.pl via Bundle.main (the .app root) or, failing that, a hardcoded ./.build path;
# it doesn't look inside the framework, so on this machine run.pl is found via the
# .build fallback. The app therefore expects to run from this source tree with ./.build
# present. (run.pl itself is now unmodified — the framework supplies the correct dylib
# path, so no patch is needed.)
ADAPTER_RESOURCES="$SCRIPT_DIR/.build/release/MediaRemoteAdapter_MediaRemoteAdapter.bundle"
if [ -d "$ADAPTER_RESOURCES" ]; then
    cp -R "$ADAPTER_RESOURCES" "$APP_BUNDLE/Contents/Resources/"
fi

# Fix rpath so the binary can find the framework at runtime.
install_name_tool -add_rpath @executable_path/../Frameworks \
    "$APP_BUNDLE/Contents/MacOS/$BINARY_NAME" 2>/dev/null || true

echo "→ Ad-hoc signing..."
# Sign the nested framework first (inside-out), then the app.
codesign --force --sign - "$FW"
codesign --force --deep --sign - \
    --entitlements "$SCRIPT_DIR/Tabr.entitlements" \
    "$APP_BUNDLE"

echo "→ Launching Tabr.app..."
open "$APP_BUNDLE"
