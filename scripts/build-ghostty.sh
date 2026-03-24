#!/bin/bash
set -euo pipefail

# Build libghostty for macOS (static library via native xcframework)
#
# Prerequisites:
#   - Zig (0.15.2+): brew install zig
#   - Ghostty source: git clone https://github.com/ghostty-org/ghostty.git
#
# Usage:
#   ./scripts/build-ghostty.sh /path/to/ghostty/source
#
# Output:
#   - lib/libghostty.a      (static library)
#   - include/ghostty.h      (C header + sub-headers)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
GHOSTTY_SRC="${1:?Usage: $0 /path/to/ghostty/source}"

if [ ! -f "$GHOSTTY_SRC/build.zig" ]; then
    echo "Error: $GHOSTTY_SRC does not look like a Ghostty source tree (no build.zig)"
    exit 1
fi

if ! command -v zig &> /dev/null; then
    echo "Error: zig is not installed. Run: brew install zig"
    exit 1
fi

echo "==> Building libghostty from $GHOSTTY_SRC"
echo "    Zig version: $(zig version)"
echo "    Target: native macOS (xcframework, static lib)"

cd "$GHOSTTY_SRC"

# Build libghostty via xcframework (native macOS only, skip Xcode app)
# - app-runtime defaults to .none on macOS (library-only, no executable)
# - xcframework-target=native avoids building for iOS / iOS Simulator
# - emit-macos-app=false skips the Xcode app bundle
zig build \
    -Doptimize=ReleaseFast \
    -Dxcframework-target=native \
    -Demit-macos-app=false

# Find the static library inside the xcframework
# The xcframework is output to macos/ (not zig-out/) by the Ghostty build system
XCFW_DIR="$GHOSTTY_SRC/macos/GhosttyKit.xcframework"
# The native xcframework has a single platform directory; library is named libghostty-fat.a
LIB_PATH=$(find "$XCFW_DIR" -name "libghostty-fat.a" -type f 2>/dev/null | head -1)
INCLUDE_PATH="$GHOSTTY_SRC/include"

if [ -z "$LIB_PATH" ]; then
    echo "Error: Build succeeded but libghostty-fat.a not found in $XCFW_DIR"
    echo "Searching for .a files:"
    find "$GHOSTTY_SRC/macos" "$GHOSTTY_SRC/zig-out" -name "*.a" -type f 2>/dev/null
    exit 1
fi

echo "    Found: $LIB_PATH"

# Copy to project
mkdir -p "$PROJECT_ROOT/lib" "$PROJECT_ROOT/include"
cp "$LIB_PATH" "$PROJECT_ROOT/lib/libghostty.a"
cp -R "$INCLUDE_PATH"/* "$PROJECT_ROOT/include/"

echo ""
echo "==> Done!"
echo "    lib/libghostty.a  — static library ($(du -h "$PROJECT_ROOT/lib/libghostty.a" | cut -f1))"
echo "    include/           — C headers"
echo ""
echo "Next: swift build"
