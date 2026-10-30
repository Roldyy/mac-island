#!/usr/bin/env bash
# Blocks a commit or a release that would carry personal data.
# Run by hand, from the pre-commit hook and from `make check`.
set -euo pipefail
cd "$(dirname "$0")/.."

bad=0
fail() { echo "BLOCKED: $1" >&2; bad=1; }

# 1. tracked or staged files that look like personal data
files=$( { git ls-files; git diff --cached --name-only; } 2>/dev/null | sort -u )
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.plist)
      case "$f" in Resources/*) ;; *) fail "plist outside Resources/: $f";; esac ;;
    */Backups/*|Backups/*|*ClipboardHistory.json|*ClipboardImages/*|*Scratchpad.json|.env*|*.p12|*.key|*.pem)
      fail "personal or secret file: $f" ;;
  esac
done <<< "$files"

# 2. content that points at the user's own machine or secrets
if [ -n "$files" ]; then
  if echo "$files" | xargs -I{} grep -IlE '/Users/[A-Za-z0-9._-]+/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{20,}' {} 2>/dev/null \
     | grep -v -e '^scripts/check-no-personal.sh$' -e '^tasks/' | grep -q .; then
    echo "$files" | xargs -I{} grep -IlE '/Users/[A-Za-z0-9._-]+/|BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ghp_[A-Za-z0-9]{20,}' {} 2>/dev/null \
      | grep -v -e '^scripts/check-no-personal.sh$' -e '^tasks/' | while read -r hit; do fail "home path or secret in: $hit"; done
  fi
fi

[ "$bad" -eq 0 ] && echo "check-no-personal: clean" || exit 1
