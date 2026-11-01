#!/usr/bin/env bash
# Lane W8A: imports the Now Playing adapter (a separate dynamic library, the only code that touches MediaRemote) and
# the perl loader from the pinned Vorssaint tree. Called by import.sh after the PortKit copy; also runnable alone:
#
#   scripts/port/import-adapter.sh <extracted-tree>
#
# Writes Sources/NowPlayingAdapter/Private{NowPlayingAdapter,NowPlayingQueue,NowPlayingSelection}.swift (the Private
# prefix marks every file that holds private symbols) and Resources/now-playing.pl, with:
#   - the exported C symbols vorssaint_now_playing_{get,watch,watch_all} renamed macisland_now_playing_*,
#   - dispatch queue labels under be.roldy.macisland,
#   - the two upstream header lines kept and the "Derived from" line added.
# The build product is libMacIslandNowPlaying.dylib (Package.swift, product MacIslandNowPlaying); bundle.sh copies it
# to Contents/Frameworks and signs it, and puts now-playing.pl in Contents/Resources.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
tree="${1:-}"
[ -d "$tree/Sources/NowPlayingAdapter" ] || { echo "usage: $0 <extracted-tree>" >&2; exit 2; }
cd "$root"

header='// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.'
dest="Sources/NowPlayingAdapter"
rm -rf "$dest"
mkdir -p "$dest"

rewrite() {
  perl -pe '
    s/vorssaint_now_playing_/macisland_now_playing_/g;
    s/vorssaintNowPlaying/macislandNowPlaying/g;
    s/com\.vorssaint\.now-playing/be.roldy.macisland.now-playing/g;
    s/`vorssaint_now_playing_get`/`macisland_now_playing_get`/g;
  ' "$1" | perl -0777 -pe '
    my $h = $ENV{PORT_HEADER};
    s/\A((?:\/\/[^\n]*\n){2})/$1$h\n/;
  '
}

export PORT_HEADER="$header"
for pair in "NowPlayingAdapter:PrivateNowPlayingAdapter" "NowPlayingQueue:PrivateNowPlayingQueue" \
            "NowPlayingSelection:PrivateNowPlayingSelection"; do
  from="${pair%%:*}"; to="${pair##*:}"
  rewrite "$tree/Sources/NowPlayingAdapter/$from.swift" > "$dest/$to.swift"
done

# The two pure files the adapter shares with the app (upstream compiles them into the library too, build.sh l.627).
for shared in NotchPlaybackSource NotchPlaybackCommand; do
  rewrite "$tree/Sources/Vorssaint/Services/Notch/$shared.swift" > "$dest/$shared.swift"
done

mkdir -p Resources
rewrite "$tree/Resources/now-playing.pl" > Resources/now-playing.pl
# The perl loader is not Swift: its header is `#` comments, so the Derived line goes in by hand.
perl -i -pe 's/^(# Copyright \(C\) 2026 Vorssaint\n)/$1# Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.\n/' Resources/now-playing.pl
chmod 644 Resources/now-playing.pl
echo "imported the Now Playing adapter ($(ls "$dest" | wc -l | tr -d ' ') files) and Resources/now-playing.pl"
