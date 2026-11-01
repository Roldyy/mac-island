#!/bin/bash
# Builds "build/Mac Island.app": release binaries, Info.plist, icon, fan helper and its daemon plist,
# then signs the helper first and the app second (never --deep).
#
#   scripts/bundle.sh                          picks our Developer ID (team U3TUL63HHK) when it is in the keychain,
#                                              signed offline (no timestamp server); else ad hoc
#   SIGN_IDENTITY=- scripts/bundle.sh          force an ad-hoc signature
#   SIGN_IDENTITY="Developer ID Application: ... (U3TUL63HHK)" scripts/bundle.sh    release signature (timestamped)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${SIGN_IDENTITY:-}"
EXPLICIT_IDENTITY=1
TEAM_ID="U3TUL63HHK"   # the fan helper's code requirement pins this team (FanHelperContract)
if [ -z "$IDENTITY" ]; then
  EXPLICIT_IDENTITY=0
  # An ad-hoc signature is identified by its cdhash, which changes on every build: macOS then keeps the
  # Accessibility / Input Monitoring / Screen Recording switch ON in System Settings while the new binary
  # no longer matches it, so the app reads "not granted". Prefer our Developer ID identity (this team only,
  # never the first Developer ID of another team) when one exists.
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n "s/.*\"\(Developer ID Application: [^\"]*(${TEAM_ID})\)\".*/\1/p" | head -n 1 || true)"
  IDENTITY="${IDENTITY:--}"   # SIGN_IDENTITY=- forces ad hoc
fi
APP="build/Mac Island.app"
APP_ID="be.roldy.macisland"
HELPER_ID="be.roldy.macisland.fanhelper"

echo "==> swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Library/LaunchDaemons"
# The Now Playing adapter (lane W8A) is never linked into the app: Resources/now-playing.pl loads the dylib into
# /usr/bin/perl, the only process MediaRemote still answers since macOS 15.4. Both files must be in the bundle
# (MediaRemoteAdapterLocator reads Contents/Resources/now-playing.pl and Contents/Frameworks/libMacIslandNowPlaying.dylib).
NOWPLAYING_DYLIB="$BIN/libMacIslandNowPlaying.dylib"
if [ ! -f "$NOWPLAYING_DYLIB" ]; then
  echo "ERROR: $NOWPLAYING_DYLIB is missing (swift build -c release --product MacIslandNowPlaying)" >&2
  exit 1
fi
cp "$NOWPLAYING_DYLIB" "$APP/Contents/Frameworks/libMacIslandNowPlaying.dylib"
cp Resources/now-playing.pl "$APP/Contents/Resources/now-playing.pl"
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
  echo "WARNING: ad-hoc signature. System permissions granted to an earlier build will not apply to this one;" >&2
  echo "         grant them again (tccutil reset All be.roldy.macisland first) after every install." >&2
  TS="--timestamp=none"; RT=""
elif [ "$EXPLICIT_IDENTITY" = 1 ]; then
  TS="--timestamp"; RT="--options runtime"          # explicit release signature: Apple timestamp server
else
  TS="--timestamp=none"; RT="--options runtime"     # picked automatically: offline-safe, still hardened runtime
fi
# shellcheck disable=SC2086
codesign --force $RT $TS -s "$IDENTITY" -i "$HELPER_ID" "$APP/Contents/MacOS/FanHelper"
# shellcheck disable=SC2086
codesign --force $RT $TS -s "$IDENTITY" -i "be.roldy.macisland.claudehook" "$APP/Contents/MacOS/ClaudeHook"
# The adapter library, signed before the app seals it. It is loaded by /usr/bin/perl (a platform binary without
# library validation, `codesign -dv /usr/bin/perl` reads flags=0x0), so the app needs no disable-library-validation
# entitlement: the app itself never loads it. The same identity keeps the signature valid under the hardened runtime.
# shellcheck disable=SC2086
codesign --force $RT $TS -s "$IDENTITY" -i "be.roldy.macisland.nowplaying" "$APP/Contents/Frameworks/libMacIslandNowPlaying.dylib"
# shellcheck disable=SC2086
codesign --force $RT $TS --entitlements Resources/MacIsland.entitlements \
  -s "$IDENTITY" -i "$APP_ID" "$APP"

echo "==> verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority|flags" || true
echo "built $APP ($VERSION, build $BUILD)"
