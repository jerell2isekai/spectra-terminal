#!/bin/bash
set -euo pipefail

# Build libghostty for macOS (embedded apprt, static library)
#
# Prerequisites:
#   - Zig (0.13+ recommended): brew install zig
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
echo "    Target: aarch64-macos (embedded apprt, static lib)"

cd "$GHOSTTY_SRC"

# Build libghostty as a static library with the embedded app runtime
zig build \
    -Doptimize=ReleaseFast \
    -Dapp-runtime=embedded \
    -Dartifact=lib \
    -Dtarget=aarch64-macos

# Find the output
LIB_PATH="$GHOSTTY_SRC/zig-out/lib/libghostty.a"
INCLUDE_PATH="$GHOSTTY_SRC/include"

if [ ! -f "$LIB_PATH" ]; then
    echo "Error: Build succeeded but libghostty.a not found at $LIB_PATH"
    echo "Check zig-out/ for the actual output path."
    exit 1
fi

# Copy to project
mkdir -p "$PROJECT_ROOT/lib" "$PROJECT_ROOT/include"
cp "$LIB_PATH" "$PROJECT_ROOT/lib/"
cp -R "$INCLUDE_PATH"/* "$PROJECT_ROOT/include/"

echo ""
echo "==> Done!"
echo "    lib/libghostty.a  — static library"
echo "    include/           — C headers"
echo ""
echo "Next: swift build"
