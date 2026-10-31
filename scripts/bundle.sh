#!/bin/bash
# Builds "build/Mac Island.app": release binaries, Info.plist, icon, fan helper and its daemon plist,
# then signs the helper first and the app second (never --deep).
#
#   scripts/bundle.sh                          ad-hoc signature, for a local build
#   SIGN_IDENTITY="Developer ID Application: ..." scripts/bundle.sh    release signature
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Mac Island.app"
APP_ID="be.roldy.macisland"
HELPER_ID="be.roldy.macisland.fanhelper"

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN/MacIsland" "$APP/Contents/MacOS/MacIsland"
cp "$BIN/FanHelper" "$APP/Contents/MacOS/FanHelper"
cp "$BIN/ClaudeHook" "$APP/Contents/MacOS/ClaudeHook"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp "Sources/Features/Fans/be.roldy.macisland.fanhelper.plist.template" \
   "$APP/Contents/Library/LaunchDaemons/$HELPER_ID.plist"
# SwiftPM resource bundles, if any dependency ships one.
for b in "$BIN"/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done

echo "==> signing with: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
  TS="--timestamp=none"; RT=""
else
  TS="--timestamp"; RT="--options runtime"
fi
# shellcheck disable=SC2086
codesign --force $RT $TS -s "$IDENTITY" -i "$HELPER_ID" "$APP/Contents/MacOS/FanHelper"
# shellcheck disable=SC2086
codesign --force $RT $TS -s "$IDENTITY" -i "be.roldy.macisland.claudehook" "$APP/Contents/MacOS/ClaudeHook"
# shellcheck disable=SC2086
codesign --force $RT $TS --entitlements Resources/MacIsland.entitlements \
  -s "$IDENTITY" -i "$APP_ID" "$APP"

echo "==> verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority|flags" || true
echo "built $APP ($VERSION, build $BUILD)"
