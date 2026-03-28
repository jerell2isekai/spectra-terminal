#!/bin/bash
set -euo pipefail

# Build a release .app bundle and package as .zip for GitHub Release upload.
#
# Usage:
#   ./scripts/build-release.sh              # auto-increment patch from latest git tag
#   ./scripts/build-release.sh 0.2.0        # explicit version
#   ./scripts/build-release.sh minor        # bump minor (0.1.x → 0.2.0)
#   ./scripts/build-release.sh major        # bump major (0.x.y → 1.0.0)
#
# Output:
#   release/Spectra-<version>-macos.zip

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Auto-detect version from latest git tag
cd "$PROJECT_ROOT"
LATEST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")
LATEST_VER="${LATEST_TAG#v}"  # strip leading v

# Parse major.minor.patch
IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_VER"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}

ARG="${1:-}"
case "$ARG" in
    major) VERSION="$((MAJOR + 1)).0.0" ;;
    minor) VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
    "")    VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;  # default: patch bump
    *)     VERSION="$ARG" ;;  # explicit version
esac

echo "    Latest tag: $LATEST_TAG → building v$VERSION"
RELEASE_DIR="$PROJECT_ROOT/release"
APP_NAME="Spectra.app"
APP="$RELEASE_DIR/$APP_NAME"

cd "$PROJECT_ROOT"

echo "==> Building Spectra v$VERSION (release)..."

# Verify libghostty exists
if [ ! -f lib/libghostty.a ]; then
    echo "Error: lib/libghostty.a not found."
    echo "Run ./scripts/build-ghostty.sh /path/to/ghostty first."
    exit 1
fi

# --- Build ---
swift build -c release 2>&1

BUILD=".build/release"
BINARY="$BUILD/Spectra"
if [ ! -f "$BINARY" ]; then
    echo "Error: Build succeeded but binary not found at $BINARY"
    exit 1
fi

# --- Create .app bundle ---
echo "==> Packaging $APP_NAME..."
rm -rf "$APP"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/Spectra"
cp -R "$BUILD/Spectra_Spectra.bundle" "$CONTENTS/Resources/Spectra_Spectra.bundle"
cp "$BUILD/Spectra_Spectra.bundle/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" << PLIST
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
    <string>${VERSION}</string>
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

# --- Strip .git directories from resources ---
echo "==> Cleaning .git from bundle resources..."
find "$APP" -name ".git" -type d -exec rm -rf {} + 2>/dev/null || true
find "$APP" -name ".gitignore" -type f -delete 2>/dev/null || true
find "$APP" -name ".DS_Store" -type f -delete 2>/dev/null || true

# --- Package as .zip ---
ZIP_NAME="Spectra-${VERSION}-macos.zip"
echo "==> Creating $ZIP_NAME..."
cd "$RELEASE_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$ZIP_NAME"

ZIP_SIZE=$(du -h "$ZIP_NAME" | cut -f1)
echo ""
echo "==> Done!"
echo "    $RELEASE_DIR/$ZIP_NAME ($ZIP_SIZE)"
echo ""
echo "Upload to GitHub Release:"
echo "    gh release create v${VERSION} $RELEASE_DIR/$ZIP_NAME --title \"Spectra v${VERSION}\" --notes \"Release v${VERSION}\""
