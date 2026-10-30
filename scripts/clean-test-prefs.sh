#!/bin/bash
# Removes preference files that early versions of the test suite left in ~/Library/Preferences.
# Only names of the form <known test prefix>-<UUID>[...].plist are touched. Dry run by default.
#   scripts/clean-test-prefs.sh          list what would be removed
#   scripts/clean-test-prefs.sh --apply  remove it
set -euo pipefail

dir="$HOME/Library/Preferences"
prefixes='clip-test|mis-tests|ka-ctrl|keepawake-test|np-test|shelf-test|display-test|AudioTests|dock-prev|dock-settings|dock-click|finder'
uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'

names="$(ls "$dir" | grep -E "^(${prefixes})-?.*${uuid}.*\.plist$" || true)"
count=0
[ -n "$names" ] && count=$(printf '%s\n' "$names" | wc -l | tr -d ' ')

echo "matching test preference files: $count"
if [ "${1:-}" != "--apply" ]; then
  [ -n "$names" ] && printf '%s\n' "$names" | head -5
  echo "dry run: pass --apply to remove them"
  exit 0
fi

printf '%s\n' "$names" | while IFS= read -r name; do
  [ -n "$name" ] && rm -f -- "$dir/$name"
done
echo "removed $count files"
