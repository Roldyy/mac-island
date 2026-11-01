#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Roldy Management
"""Language trim of the ported strings (lane W9D): Mac Island's UI is French, English is kept as the base table.

Every other language of the 15 Vorssaint ships is removed from the Swift sources under Sources/PortKit:

  1. `static let <lang> = Type( ... )` tables (4-space indent, closed by a line that is exactly `    )`) are deleted.
  2. Inside a `switch` over a language (`switch language {`, `switch l10n.language {`, `switch self {` in AppLanguage),
     every `case .<lang>...:` group whose labels are all removed languages is deleted. A group is the label line and
     everything under it up to the next label of the same indentation, or the closing brace.
  3. A switch that lost cases still has to be exhaustive over the 15-case `AppLanguage`: its `.fr` group becomes the
     `default:` group (so every language that is not English reads French). The `.fr` group must then be the last one;
     the script stops with the file name when it is not.

The enum `AppLanguage` itself keeps its 15 cases (other code names them), but no table exists for the 13 dropped ones.
Run it from the repo root:  python3 -I scripts/port/trim-languages.py [--check] [Sources/PortKit]
`--check` changes nothing and exits 1 when a file would change (the grep gate of the import).
Idempotent: a second run finds nothing to remove.
"""
import re
import sys
from pathlib import Path

DROPPED = ["ptBR", "tr", "ru", "es", "sk", "de", "it", "ja", "ko", "uk", "zhHans", "zhTW", "zhHK"]
KEPT = ["enUS", "fr"]
ALL = DROPPED + KEPT

STATIC_START = re.compile(r"^    static let (%s) = " % "|".join(DROPPED))
STATIC_END = re.compile(r"^    \)\s*$")
CASE_LABEL = re.compile(r"^(\s*)case ((?:\.\w+)(?:\s*,\s*\.\w+)*)\s*:(.*)$")
DEFAULT_LABEL = re.compile(r"^(\s*)default\s*:")


def labels_of(text):
    return [t.strip().lstrip(".") for t in text.split(",")]


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def strip_static_tables(lines, name):
    out, i, removed = [], 0, 0
    while i < len(lines):
        if STATIC_START.match(lines[i]):
            # The table runs while lines are blank, indented 8+ (its arguments) or the lone `    )` that closes it;
            # it can also close inline on its last argument. The next 4-indent declaration, comment or brace ends it.
            j = i + 1
            while j < len(lines) and (lines[j].strip() == "" or indent_of(lines[j]) >= 8 or STATIC_END.match(lines[j])):
                j += 1
            if j >= len(lines):
                raise SystemExit(f"{name}:{i + 1}: table never ends")
            i = j
            removed += 1
        else:
            out.append(lines[i])
            i += 1
    return out, removed


def find_groups(lines, switch_index):
    """The case groups of the switch opened at `switch_index`: (start, end_exclusive, labels, indent)."""
    base = indent_of(lines[switch_index])
    groups, i = [], switch_index + 1
    case_indent = None
    while i < len(lines):
        line = lines[i]
        if line.strip() and indent_of(line) <= base and line.lstrip().startswith("}"):
            break  # the closing brace of the switch (a comment or a `)` at case indentation does not end it)
        m = CASE_LABEL.match(line)
        d = DEFAULT_LABEL.match(line)
        here = indent_of(line)
        if (m or d) and (case_indent is None or here == case_indent) and here <= base + 4:
            case_indent = here
            groups.append([i, None, labels_of(m.group(2)) if m else ["default"], here])
        i += 1
    for n, g in enumerate(groups):
        g[1] = groups[n + 1][0] if n + 1 < len(groups) else i
    return [tuple(g) for g in groups], i


SWITCH_LINE = re.compile(r"^\s*switch\s+(?:language|l10n\.language|self|lang|appLanguage|[A-Za-z_.]*[lL]anguage)\s*\{\s*$")


def trim_switches(lines, name):
    changed = 0
    i = 0
    while i < len(lines):
        if SWITCH_LINE.match(lines[i]):
            groups, end = find_groups(lines, i)
            language_groups = [g for g in groups if any(lbl in ALL for lbl in g[2])]
            if not language_groups:
                i += 1
                continue
            doomed = [g for g in groups if all(lbl in DROPPED for lbl in g[2])]
            if not doomed:
                i += 1
                continue
            # delete from the bottom so indices hold
            for g in sorted(doomed, key=lambda g: -g[0]):
                del lines[g[0]:g[1]]
            changed += len(doomed)
            groups, end = find_groups(lines, i)
            kept_langs = {lbl for g in groups for lbl in g[2]}
            has_default = "default" in kept_langs
            if not has_default:
                fr = [g for g in groups if g[2] == ["fr"]]
                if not fr:
                    raise SystemExit(f"{name}:{i + 1}: no `case .fr` group left to become the default")
                fr = fr[0]
                if fr is groups[-1]:
                    lines[fr[0]] = re.sub(r"case \.fr\s*:", "default:", lines[fr[0]], count=1)
                else:
                    # `.fr` is followed by another kept group (English): a default must come last, so it gets a copy
                    # of the French body and `.fr` stays a case of its own.
                    copy = list(lines[fr[0]:fr[1]])
                    copy[0] = re.sub(r"case \.fr\s*:", "default:", copy[0], count=1)
                    insert_at = groups[-1][1]
                    lines[insert_at:insert_at] = copy
            i += 1
        else:
            i += 1
    return lines, changed


def trim(path: Path):
    text = path.read_text()
    lines = text.split("\n")
    lines, tables = strip_static_tables(lines, str(path))
    lines, groups = trim_switches(lines, str(path))
    new = "\n".join(lines)
    return new, tables, groups, new != text


def main(argv):
    check = "--check" in argv
    roots = [a for a in argv if not a.startswith("--")] or ["Sources/PortKit"]
    dirty, tables, groups = [], 0, 0
    for root in roots:
        for path in sorted(Path(root).rglob("*.swift")):
            new, t, g, changed = trim(path)
            if not changed:
                continue
            dirty.append(str(path))
            tables += t
            groups += g
            if not check:
                path.write_text(new)
    print(f"{'would change' if check else 'changed'} {len(dirty)} files: {tables} tables, {groups} case groups")
    return 1 if (check and dirty) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
