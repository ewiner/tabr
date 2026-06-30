#!/bin/bash
# Builds Tabr as a proper .app bundle and ad-hoc signs it.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$SCRIPT_DIR/Tabr.app"
BINARY_NAME="Tabr"

echo "→ Building..."
swift build -c release --package-path "$SCRIPT_DIR" 2>&1

BINARY="$SCRIPT_DIR/.build/release/$BINARY_NAME"

# --- macOS 26 dylib-load fix ---
# MediaRemoteAdapter ships as a loose dylib, so at runtime the app hands run.pl the
# path to the MAIN EXECUTABLE (Bundle(for:).executablePath resolves to the app, not
# the dylib). That binary depends on @rpath/libMediaRemoteAdapter.dylib, and macOS 26
# refuses to expand @rpath when a foreign process (perl) dlopen()s it ("security
# policy does not allow @ path expansion") — so Now Playing silently stops working.
# Patch run.pl to redirect an executable path to the real adapter dylib, which loads
# fine by absolute path. Patch both the package's source copy (so future swift builds
# inherit it) and the built copy the app actually loads via Bundle.module.
patch_runpl() {
    local f="$1"
    [ -f "$f" ] || return 0
    grep -q "Tabr/macOS26 fix" "$f" && return 0
    chmod u+w "$f"
    /usr/bin/perl -0777 -i -pe 's{(unless \(-e \$dylib_path\) \{\n    die "Dynamic library not found at \$dylib_path\\n";\n\})}{$1\n\n# Tabr/macOS26 fix: the host app passes the main executable path, but macOS now\n# blocks \@rpath expansion when perl dlopens it. Redirect to the real adapter\n# dylib, which loads fine by absolute path.\nif (\$dylib_path !~ /\\.dylib\$/) \{\n    (my \$fw = \$dylib_path) =~ s\{/Contents/MacOS/\[^/\]+\$\}\{/Contents/Frameworks\};\n    if (-d \$fw) \{\n        my (\$real) = glob("\$fw/libMediaRemoteAdapter*.dylib");\n        \$dylib_path = \$real if \$real \&\& -e \$real;\n    \}\n\}}s' "$f"
    echo "  ✓ patched run.pl for macOS 26 @rpath dlopen restriction: $f"
}
patch_runpl "$SCRIPT_DIR/.build/checkouts/mediaremote-adapter/Sources/MediaRemoteAdapter/Resources/run.pl"
patch_runpl "$SCRIPT_DIR/.build/release/MediaRemoteAdapter_MediaRemoteAdapter.bundle/run.pl"

echo "→ Creating app bundle..."
# Start from a clean bundle. cp -R can't overwrite the read-only resources copied
# by a previous build (e.g. run.pl), so a stale bundle would break re-runs.
rm -rf "$APP_BUNDLE"
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

# Copy the Perl script and C helper from the (now-patched) package resources.
# NOTE: SPM's generated Bundle.module first looks for this bundle next to
# Bundle.main.bundleURL (the .app root) and otherwise falls back to a hardcoded
# ./.build path. We can't place a copy at the .app root (codesign rejects
# "unsealed contents in the bundle root"), so on this machine the app loads run.pl
# via the .build fallback — which build.sh patches above. The app therefore expects
# to be run from this source tree with ./.build present.
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
