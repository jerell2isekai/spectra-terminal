#!/bin/bash
set -euo pipefail

# Development build & run — debug mode, runs directly from .build/
#
# Usage:
#   ./scripts/run-dev.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Verify libghostty exists
if [ ! -f lib/libghostty.a ]; then
    echo "Error: lib/libghostty.a not found."
    echo "Run ./scripts/build-ghostty.sh /path/to/ghostty first."
    exit 1
fi

echo "==> Building Spectra (debug)..."
swift build 2>&1

BINARY=".build/debug/Spectra"
if [ ! -f "$BINARY" ]; then
    echo "Error: Build succeeded but binary not found at $BINARY"
    exit 1
fi

echo "==> Running Spectra (debug)..."
exec "$BINARY"
