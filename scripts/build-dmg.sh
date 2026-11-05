#!/usr/bin/env bash
# Builds E-Merger.app and packages it into a drag-to-install .dmg.
# Usage: scripts/build-dmg.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-dev}"
DIST="$(pwd)/dist"
DMG="$DIST/E-Merger-$VERSION.dmg"
STAGE="$(mktemp -d)/E-Merger"

scripts/build-app.sh Release

mkdir -p "$STAGE"
cp -R "$DIST/E-Merger.app" "$STAGE/E-Merger.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "E-Merger" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGE"
echo "✓ $DMG"
shasum -a 256 "$DMG"
