#!/usr/bin/env bash
# Build, Developer-ID sign, notarize, staple, and package E-Merger into a .dmg.
# Used by CI for tagged releases. Requires a Developer ID Application identity in
# the keychain and an App Store Connect API key for notarytool.
#
# Required environment:
#   SIGNING_IDENTITY  e.g. "Developer ID Application: Jane Doe (ABCDE12345)"
#   ASC_KEY_PATH      path to the App Store Connect API .p8
#   ASC_KEY_ID        API Key ID
#   ASC_ISSUER_ID     API Issuer ID
# Usage: scripts/release-dmg.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release-dmg.sh <version>}"
: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH}"
: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"

DIST="$(pwd)/dist"
APP="$DIST/E-Merger.app"
DMG="$DIST/E-Merger-$VERSION.dmg"
STAGE="$(mktemp -d)/E-Merger"

# 1. Build (unsigned, version-stamped). Stamping the tag version in lets Sparkle
#    compare the running app against the appcast.
scripts/build-app.sh Release "$VERSION"

# 2. Sign the embedded Sparkle.framework inside-out BEFORE the outer app — signing
#    the app seals its contents, so every nested executable must already be signed.
#    The build is unsigned (CODE_SIGNING_ALLOWED=NO), so we sign all of Sparkle's
#    helpers ourselves with Developer ID + hardened runtime + timestamp.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  SPV="$SPARKLE/Versions/B"
  # XPC services ship with their own entitlements (Downloader is sandboxed) — keep them.
  for xpc in "$SPV/XPCServices/Installer.xpc" "$SPV/XPCServices/Downloader.xpc"; do
    [[ -e "$xpc" ]] && codesign --force --options runtime --timestamp \
      --preserve-metadata=entitlements,requirements,flags \
      --sign "$SIGNING_IDENTITY" "$xpc"
  done
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SPV/Autoupdate"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SPV/Updater.app"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$SPARKLE"
fi

# 3. Sign the outer app last (seals the now-signed framework).
codesign --force --options runtime --timestamp \
  --entitlements EMerger/EMerger.entitlements \
  --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 2. Notarize the app and staple the ticket (so it launches offline too).
ditto -c -k --keepParent "$APP" "$DIST/E-Merger.zip"
xcrun notarytool submit "$DIST/E-Merger.zip" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$APP"
rm -f "$DIST/E-Merger.zip"

# 3. Package the stapled app into a drag-to-install DMG.
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/E-Merger.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "E-Merger" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

# 4. Sign, notarize + staple the DMG itself, so Gatekeeper accepts the disk image
#    as well as the app inside (`spctl -a -t open` on the DMG passes).
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" \
  --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
xcrun stapler staple "$DMG"

echo "✓ $DMG"
shasum -a 256 "$DMG"
