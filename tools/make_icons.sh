#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ROOT/build"
ICNS="Resources/AppIcon.icns"

echo "==> Rendering iconset"
rm -rf "$ICONSET"
swift tools/make_icon.swift "$ICONSET"

echo "==> Compiling $ICNS"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo ""
echo "Done. $ICNS ($(du -h "$ICNS" | cut -f1))"
