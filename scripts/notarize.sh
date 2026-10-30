#!/bin/bash
# Signs, notarizes and staples "build/Mac Island.app", then builds a signed, notarized DMG.
#
# One-time setup, typed by you in a terminal (stores the credentials in your keychain, never in this repo):
#   xcrun notarytool store-credentials "mac-island-notary" --apple-id <id> --team-id U3TUL63HHK
#
# Then:
#   SIGN_IDENTITY="Developer ID Application: istarii (U3TUL63HHK)" scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-mac-island-notary}"
IDENTITY="${SIGN_IDENTITY:?set SIGN_IDENTITY to your Developer ID Application identity}"
APP="build/Mac Island.app"
DMG="build/MacIsland.dmg"
ZIP="build/MacIsland-notarize.zip"

SIGN_IDENTITY="$IDENTITY" scripts/bundle.sh

echo "==> notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
rm -f "$ZIP"

echo "==> building the DMG"
STAGE="build/dmg-stage"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Mac Island" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp -s "$IDENTITY" "$DMG"

echo "==> notarizing the DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> checks"
spctl -a -t exec -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"
( cd build && shasum -a 256 "MacIsland.dmg" > "MacIsland.dmg.sha256" )
cat build/MacIsland.dmg.sha256
echo "ready to publish: $DMG and $DMG.sha256"
