#!/usr/bin/env bash
# Re-runnable import of Vorssaint (pinned in scripts/port/UPSTREAM) into Sources/PortKit.
#
#   scripts/port/import.sh <extracted-tree | archive.tgz> [--no-patches] [--trust-dir]
#
# An archive is checked against UPSTREAM tgz_sha256; a directory against tree_sha256 (sha256 of the sorted
# "path + file sha256" list, symbolic links refused) unless --trust-dir says otherwise.
#
# Copies Sources/Vorssaint with its layout kept (minus scripts/port/drop.txt), then:
#   1. rewrites the brand (bare word "Vorssaint" on non-comment lines) and the com.vorssaint identifiers,
#   2. rewrites the 8 `(NSApp.delegate as? AppDelegate)` casts to `appDelegate()`,
#   3. cuts the Portuguese table out of Localization.swift,
#   4. adds the "Derived from Vorssaint" header under the existing GPL header,
#   5. copies the two system-library targets and extracts BlackHoleGlyph into Compat/,
#   6. applies scripts/port/patches/*.patch in name order (skipped with --no-patches, which is how the
#      pristine tree is produced to regenerate a patch).
# Hand-written code (Sources/PortKit/Compat except BlackHoleGlyph.swift, Sources/PortKit/Bridge) is never touched.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

input="${1:-}"
apply_patches=1
trust_dir=0
[ -n "$input" ] || { echo "usage: $0 <extracted-tree | archive.tgz> [--no-patches] [--trust-dir]" >&2; exit 2; }
shift
for flag in "$@"; do
  case "$flag" in
    --no-patches) apply_patches=0 ;;
    --trust-dir) trust_dir=1 ;;
    *) echo "unknown option: $flag" >&2; exit 2 ;;
  esac
done

upstream() { sed -n "s/^$1=//p" scripts/port/UPSTREAM; }
expected_sha="$(upstream tgz_sha256)"
expected_tree="$(upstream tree_sha256)"

# sha256 over the sorted (relative path, file sha256) list: names and contents, not owners or times.
tree_hash() {
  (cd "$1" && LC_ALL=C find . -type f -print0 | LC_ALL=C sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}')
}

tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; return 0; }
trap cleanup EXIT

if [ -f "$input" ]; then
  actual="$(shasum -a 256 "$input" | awk '{print $1}')"
  [ "$actual" = "$expected_sha" ] || { echo "archive sha256 $actual does not match UPSTREAM" >&2; exit 1; }
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/port.XXXXXX")"
  tar -xzf "$input" -C "$tmp"
  tree="$(find "$tmp" -maxdepth 1 -mindepth 1 -type d | head -1)"
else
  tree="$input"
  # A directory is code we are about to copy and rewrite: it must be the pinned tree (UPSTREAM tree_sha256),
  # or the caller says --trust-dir on purpose.
  if [ "$trust_dir" = 1 ]; then
    echo "warning: --trust-dir, the tree is not verified against UPSTREAM" >&2
  else
    [ -n "$expected_tree" ] || { echo "UPSTREAM has no tree_sha256: pass the archive, or --trust-dir" >&2; exit 1; }
    [ -d "$tree" ] || { echo "not a directory or archive: $tree" >&2; exit 1; }
    [ -z "$(find "$tree" -type l | head -1)" ] || { echo "symbolic link in $tree: refused (use the archive)" >&2; exit 1; }
    actual_tree="$(tree_hash "$tree")"
    [ "$actual_tree" = "$expected_tree" ] || {
      echo "tree sha256 $actual_tree does not match UPSTREAM: pass the archive, or --trust-dir" >&2; exit 1; }
  fi
fi
src="$tree/Sources/Vorssaint"
[ -d "$src" ] || { echo "no Sources/Vorssaint in $tree" >&2; exit 1; }

dest="Sources/PortKit"
header='// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.'

# --- 1. copy, minus the drop list -----------------------------------------------------------------------
for d in App Core Services Support UI; do rm -rf "${dest:?}/$d"; done
mkdir -p "$dest"

dropped() {
  local rel="$1" entry
  while IFS= read -r entry; do
    case "$entry" in ''|'#'*) continue ;; esac
    case "$entry" in
      */) case "$rel" in "$entry"*) return 0 ;; esac ;;
      *) [ "$rel" = "$entry" ] && return 0 ;;
    esac
  done < scripts/port/drop.txt
  return 1
}

count=0
while IFS= read -r -d '' file; do
  rel="${file#"$src"/}"
  if dropped "$rel"; then continue; fi
  mkdir -p "$dest/$(dirname "$rel")"
  cp "$file" "$dest/$rel"
  count=$((count + 1))
done < <(find "$src" -type f -name '*.swift' -print0 | sort -z)
echo "copied $count Swift files"

# --- 2. text rewrites (copied folders only: Compat/ and Bridge/ are hand-written and never rewritten) -------
copied=("$dest/App" "$dest/Core" "$dest/Services" "$dest/UI")
find "${copied[@]}" -type f -name '*.swift' -print0 | xargs -0 perl -i -pe '
  s/\(NSApp\.delegate as\? AppDelegate\)/appDelegate()/g;
  s{Application Support/com\.vorssaint\.utils}{Application Support/be.roldy.macisland}g;
  s{\?\? "com\.vorssaint\.utils"}{?? "be.roldy.macisland"}g;
  s/"com\.vorssaint\."(?=\s*\+)/"be.roldy.macisland."/g;
  s/com\.vorssaint\.utils\.(?=[A-Za-z])/be.roldy.macisland./g;
  s/com\.vorssaint\.(?!utils\b)(?=[A-Za-z])/be.roldy.macisland./g;
  unless (/^\s*\/\//) { s/\bVorssaint(?:u)?\b/Mac Island/g; }
'

# Portuguese out: from its MARK line up to the English one.
perl -i -ne '
  if (/^\/\/ MARK: - Portugu/) { $skip = 1 }
  if (/^\/\/ MARK: - English \(US\)/) { $skip = 0 }
  print unless $skip;
' "$dest/Core/Localization.swift"

# --- 3. header ------------------------------------------------------------------------------------------
find "${copied[@]}" -type f -name '*.swift' -print0 | PORT_HEADER="$header" xargs -0 perl -i -0777 -pe '
  my $h = $ENV{PORT_HEADER};
  unless (s/\A((?:\/\/[^\n]*\n){2})/$1$h\n/) { $_ = "$h\n" . $_ }
'

# --- 4. system-library targets and BlackHoleGlyph ----------------------------------------------------------
for t in HIDEventSystem VMStatisticsCompat; do
  rm -rf "Sources/$t"
  mkdir -p "Sources/$t/include"
  cp "$tree/Sources/$t/module.modulemap" "Sources/$t/module.modulemap"
  cp "$tree/Sources/$t/include/"* "Sources/$t/include/"
  for f in "Sources/$t/module.modulemap" "Sources/$t/include/"*; do
    printf '%s\n' "$header" | cat - "$f" > "$f.new" && mv "$f.new" "$f"
  done
done

# The Now Playing adapter (lane W8A): its own dynamic library and the perl loader, never part of PortKit.
bash scripts/port/import-adapter.sh "$tree"

mkdir -p "$dest/Compat"
{
  printf '%s\n' '// SPDX-License-Identifier: GPL-3.0-or-later' '// Copyright (C) 2026 Vorssaint' "$header"
  printf '%s\n' '// Generated by scripts/port/import.sh from App/StatusItemController.swift (the rest of that file is dropped).' '' 'import AppKit' 'import SwiftUI' ''
  perl -ne 'print if /^enum BlackHoleGlyph/ .. eof' "$src/App/StatusItemController.swift" |
    perl -pe 's/\bVorssaint\b/Mac Island/g unless /^\s*\/\//'
} > "$dest/Compat/BlackHoleGlyph.swift"

# --- 5. patches -----------------------------------------------------------------------------------------
if [ "$apply_patches" = 1 ]; then
  for p in scripts/port/patches/*.patch; do
    [ -e "$p" ] || continue
    patch -p1 -s --no-backup-if-mismatch -d "$dest" -i "$root/$p" || { echo "patch failed: $p" >&2; exit 1; }
    echo "applied $(basename "$p")"
  done
fi
find "$dest" \( -name '*.orig' -o -name '*.rej' \) -delete
echo "done: $dest"
