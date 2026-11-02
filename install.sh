#!/bin/bash
# Mac Island installer. It downloads the DMG of the latest release, checks the checksum and the
# signature, and copies the app to /Applications. The release is signed with a Developer ID but not
# notarized; because this script (and not a browser) copies the app, macOS puts no quarantine flag on it
# and Gatekeeper does not block the first launch.
#
#   curl -fsSL https://raw.githubusercontent.com/Roldyy/mac-island/main/install.sh | bash
#
# Read it first if you like: it is short, and it does not use sudo.
set -euo pipefail

REPO="Roldyy/mac-island"
TEAM_ID="U3TUL63HHK"
APP_NAME="Mac Island.app"
BASE="https://github.com/$REPO/releases/latest/download"

say() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "Mac Island runs on macOS only."
[ "$(uname -m)" = "arm64" ] || die "Mac Island needs an Apple silicon Mac."
major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || die "Mac Island needs macOS 14 or later (this Mac runs $(sw_vers -productVersion))."

work="$(mktemp -d)"
mount_point="$work/mount"
cleanup() {
  if [ -d "$mount_point" ]; then hdiutil detach "$mount_point" -quiet 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

say "Downloading the latest release"
curl -fsSL "$BASE/MacIsland.dmg" -o "$work/MacIsland.dmg"
curl -fsSL "$BASE/MacIsland.dmg.sha256" -o "$work/MacIsland.dmg.sha256"

say "Checking the checksum"
expected="$(awk '{print $1}' "$work/MacIsland.dmg.sha256")"
actual="$(shasum -a 256 "$work/MacIsland.dmg" | awk '{print $1}')"
[ -n "$expected" ] && [ "$expected" = "$actual" ] || die "checksum mismatch, nothing was installed."

say "Mounting the disk image"
mkdir -p "$mount_point"
hdiutil attach "$work/MacIsland.dmg" -nobrowse -readonly -mountpoint "$mount_point" -quiet
src="$mount_point/$APP_NAME"
[ -d "$src" ] || die "the disk image does not contain $APP_NAME."

say "Checking the signature"
codesign --verify --deep --strict "$src" || die "the app signature is not valid, nothing was installed."
found_team="$(codesign -dv "$src" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[ "$found_team" = "$TEAM_ID" ] || die "unexpected signing team '$found_team', nothing was installed."
# Not notarized: spctl reports it as an unnotarized Developer ID app, which is expected. The checksum, the
# signature and the team identifier above are what this script relies on.

if pgrep -x MacIsland >/dev/null 2>&1; then
  say "Quitting the running Mac Island"
  pkill -x MacIsland || true
  sleep 1
fi

say "Installing to /Applications"
rm -rf "/Applications/$APP_NAME"
cp -R "$src" "/Applications/$APP_NAME"

say "Starting Mac Island"
open "/Applications/$APP_NAME"
cat <<'EOF'

Done. Move the pointer over the notch to open the island.
Permissions (Accessibility, Screen Recording, Automation, audio capture) are requested only when you
turn on the feature that needs them. Nothing is prompted at launch.
EOF
