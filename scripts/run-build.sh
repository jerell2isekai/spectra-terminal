#!/bin/bash
set -euo pipefail

# Production build & deploy — release mode, creates .app bundle in /Applications
#
# Usage:
#   ./scripts/run-build.sh              # build + deploy + launch
#   ./scripts/run-build.sh --no-launch  # build + deploy only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
APP="/Applications/Spectra.app"
LAUNCH=true

for arg in "$@"; do
    case "$arg" in
        --no-launch) LAUNCH=false ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

cd "$PROJECT_ROOT"

# Verify libghostty exists
if [ ! -f lib/libghostty.a ]; then
    echo "Error: lib/libghostty.a not found."
    echo "Run ./scripts/build-ghostty.sh /path/to/ghostty first."
    exit 1
fi

# --- Build ---
echo "==> Building Spectra (release)..."
swift build -c release 2>&1

BUILD=".build/release"
BINARY="$BUILD/Spectra"
if [ ! -f "$BINARY" ]; then
    echo "Error: Build succeeded but binary not found at $BINARY"
    exit 1
fi

# --- Regenerate .icns if source PNG is newer ---
ICON_SRC="assets/spectra-icon-v2.png"
ICON_ICNS="Sources/Spectra/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ] && [ "$ICON_SRC" -nt "$ICON_ICNS" ]; then
    echo "==> Icon source updated, regenerating .icns..."
    rm -rf assets/AppIcon.iconset && mkdir -p assets/AppIcon.iconset
    for size in 16 32 128 256 512; do
        sips -s format png -z $size $size "$ICON_SRC" \
            --out "assets/AppIcon.iconset/icon_${size}x${size}.png" > /dev/null 2>&1
        double=$((size * 2))
        sips -s format png -z $double $double "$ICON_SRC" \
            --out "assets/AppIcon.iconset/icon_${size}x${size}@2x.png" > /dev/null 2>&1
    done
    iconutil -c icns assets/AppIcon.iconset -o "$ICON_ICNS"
    rm -rf assets/AppIcon.iconset
    echo "    Rebuilt $ICON_ICNS"
    # Rebuild to pick up new icon resource
    swift build -c release 2>&1
fi

# --- Create .app bundle ---
echo "==> Packaging Spectra.app..."
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Spectra"
cp -R "$BUILD/Spectra_Spectra.bundle" "$CONTENTS/Resources/Spectra_Spectra.bundle"
cp "$BUILD/Spectra_Spectra.bundle/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Spectra</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.spectra.terminal</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Spectra</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Refresh Launch Services icon cache
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" 2>/dev/null || true

echo "==> Deployed to $APP"

# --- Launch ---
if [ "$LAUNCH" = true ]; then
    echo "==> Launching Spectra..."
    open "$APP"
fi
